# docker-openresty-lua-proxy
A docker container set up be a reverse proxy powered by redis and openresty

Set a frontend association with a backend pool

redis-cli set frontend:example.com example

Add backends to the pool

redis-cli rpush backend:example http://192.168.0.42:80
redis-cli rpush backend:example http://192.168.0.43:80

Review the backends for a pool

redis-cli lrange backend:example 0 -1
