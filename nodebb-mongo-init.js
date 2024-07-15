db.createUser({
  user: "navystack-mongo",
  pwd: "oVvzozYfCgZXJ7373Y9VvmXh0J8WyF",
  roles: [
    { role: "readWrite", db: "navystack-mongo" },
    { role: "clusterMonitor", db: "admin" },
  ],
});
