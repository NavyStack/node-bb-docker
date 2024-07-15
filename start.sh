#!/bin/bash

set -e

set_defaults() {
  export CONFIG_DIR="${CONFIG_DIR:-/opt/config}"
  export CONFIG="$CONFIG_DIR/config.json"
  export NODEBB_INIT_VERB="${NODEBB_INIT_VERB:-install}"
  export START_BUILD="${START_BUILD:-false}"
  export SETUP="${SETUP:-}"
  export PACKAGE_MANAGER="${PACKAGE_MANAGER:-npm}"
  export OVERRIDE_UPDATE_LOCK="${OVERRIDE_UPDATE_LOCK:-false}"

  export DEFAULT_USER="${CONTAINER_USER:-nodebb}"
  export HOME_DIR="/home/$DEFAULT_USER"
  export APP_DIR="/usr/src/app/"
  export HOME="$HOME_DIR"
  export LOG_DIR="$APP_DIR/logs"
  export BUILD_DIR="$APP_DIR/build"
}

check_directory() {
  local dir="$1"
  [ -d "$dir" ] || {
    echo "Directory $dir does not exist. Creating..."
    mkdir -p "$dir"
  }
  [ -w "$dir" ] || {
    echo "No write permission for directory $dir"
    exit 1
  }
}

copy_or_link_files() {
  local src_dir="$1"
  local dest_dir="$2"
  local package_manager="$3"
  local lock_file

  case "$package_manager" in
    yarn) lock_file="yarn.lock" ;;
    npm) lock_file="package-lock.json" ;;
    pnpm) lock_file="pnpm-lock.yaml" ;;
    *)
      echo "Unknown package manager: $package_manager"
      exit 1
      ;;
  esac

  [ "$(realpath "$src_dir/package.json")" != "$(realpath "$dest_dir/package.json")" ] && cp "$src_dir/package.json" "$dest_dir/package.json"
  [ "$(realpath "$src_dir/$lock_file")" != "$(realpath "$dest_dir/$lock_file")" ] && cp "$src_dir/$lock_file" "$dest_dir/$lock_file"

  rm -f "$src_dir/"{yarn.lock,package-lock.json,pnpm-lock.yaml}
  ln -fs "$dest_dir/package.json" "$src_dir/package.json"
  ln -fs "$dest_dir/$lock_file" "$src_dir/$lock_file"

  chown -h "$DEFAULT_USER:$DEFAULT_USER" "$src_dir/package.json" "$src_dir/$lock_file"
  chown "$DEFAULT_USER:$DEFAULT_USER" "$dest_dir/package.json" "$dest_dir/$lock_file"
}

install_dependencies() {
  case "$PACKAGE_MANAGER" in
    yarn) gosu nodebb yarn install ;;
    npm) gosu nodebb npm install ;;
    pnpm) gosu nodebb pnpm install ;;
    *)
      echo "Unknown package manager: $PACKAGE_MANAGER"
      exit 1
      ;;
  esac || {
    echo "Failed to install dependencies with $PACKAGE_MANAGER"
    exit 1
  }
}

start_setup_session() {
  local config="$1"
  echo "Starting setup session"
  gosu nodebb /usr/src/app/nodebb setup --config="$config"
}

start_forum() {
  local config="$1"
  local start_build="$2"

  echo "Starting forum"
  [ "$start_build" = true ] && {
    echo "Building..."
    gosu nodebb /usr/src/app/nodebb build --config="$config" || {
      echo "Failed to build NodeBB. Exiting..."
      exit 1
    }
  }

  case "$PACKAGE_MANAGER" in
    yarn) gosu nodebb yarn start --config="$config" --no-silent --no-daemon ;;
    npm) gosu nodebb npm start -- --config="$config" --no-silent --no-daemon ;;
    pnpm) gosu nodebb pnpm start -- --config="$config" --no-silent --no-daemon ;;
    *)
      echo "Unknown package manager: $PACKAGE_MANAGER"
      exit 1
      ;;
  esac || {
    echo "Failed to start forum with $PACKAGE_MANAGER"
    exit 1
  }
}

start_installation_session() {
  local nodebb_init_verb="$1"
  local config="$2"

  echo "Config file not found at $config"
  echo "Starting installation session"
  gosu nodebb /usr/src/app/nodebb "$nodebb_init_verb" --config="$config"
}

main() {
  set_defaults

  if [ "$(id -u)" = '0' ]; then
    if [ -n "$UID" ] && [ -n "$GID" ]; then
      echo "Using provided UID = $UID / GID = $GID"
      usermod -u "$UID" nodebb
      groupmod -g "$GID" nodebb
    else
      echo "Using Default UID:GID (1001:1001)"
    fi

    echo "Starting with UID/GID: $(id -u "nodebb")/$(getent group "nodebb" | cut -d ":" -f 3)"
    install -d -o nodebb -g nodebb -m 700 "$HOME_DIR" "$APP_DIR" "$CONFIG_DIR"
    chown -R "nodebb:nodebb" "$HOME_DIR" "$APP_DIR" "$CONFIG_DIR" "$BUILD_DIR"
  fi

  check_directory "$CONFIG_DIR"
  copy_or_link_files /usr/src/app "$CONFIG_DIR" "$PACKAGE_MANAGER"
  install_dependencies

  if [ -n "$SETUP" ]; then
    start_setup_session "$CONFIG"
  elif [ -f "$CONFIG" ]; then
    start_forum "$CONFIG" "$START_BUILD"
  else
    start_installation_session "$NODEBB_INIT_VERB" "$CONFIG"
  fi
}

main "$@"
