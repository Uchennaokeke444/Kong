use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
do "./t/Util.pm";

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.set_header() errors if arguments are not given
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_header)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid header name "nil": got nil, expected string
--- no_error_log
[error]



=== TEST 2: service.request.set_header() errors if header is not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_header, 127001, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid header name "127001": got number, expected string
--- no_error_log
[error]



=== TEST 3: service.request.set_header() errors if value is of a bad type
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_header, "foo", function() end)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid header value for "foo": got function, expected array of string, string, number or boolean
--- no_error_log
[error]



=== TEST 4: service.request.set_header() errors if value is not given
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_header, "foo")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
invalid header value for "foo": got nil, expected array of string, string, number or boolean
--- no_error_log
[error]



=== TEST 5: service.request.set_header("Host") sets Host header sent to the service
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("host: ", ngx.req.get_headers()["Host"])
            }
        }
    }
}
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            ngx.ctx.balancer_data = {
                host = "foo.xyz"
            }

            pdk.service.request.set_header("Host", "example.com")

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
host: example.com
--- no_error_log
[error]



=== TEST 6: service.request.set_header() sets a header in the request to the service
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("X-Foo", "hello world")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {hello world}
--- no_error_log
[error]



=== TEST 7: service.request.set_header() sets a header given a number
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("X-Foo", 2.5)

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {2.5}
--- no_error_log
[error]



=== TEST 8: service.request.set_header() sets a header given a boolean
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("X-Foo", false)

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {false}
--- no_error_log
[error]



=== TEST 9: service.request.set_header() replaces all headers with that name if any exist
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: ", tostring(ngx.req.get_headers()["X-Foo"]))
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("X-Foo", "hello world")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- more_headers
X-Foo: bla bla
X-Foo: baz
--- response_body
X-Foo: hello world
--- no_error_log
[error]



=== TEST 10: service.request.set_header() can set to an empty string
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("X-Foo", "")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {}
--- no_error_log
[error]



=== TEST 11: service.request.set_header() ignores spaces in the beginning of value
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("X-Foo", "     hello")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {hello}
--- no_error_log
[error]



=== TEST 12: service.request.set_header() ignores spaces in the end of value
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.say("X-Foo: {" .. ngx.req.get_headers()["X-Foo"] .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("X-Foo", "hello       ")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {hello}
--- no_error_log
[error]



=== TEST 13: service.request.set_header() can differentiate empty string from unset
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                local headers = ngx.req.get_headers()
                ngx.say("X-Foo: {" .. headers["X-Foo"] .. "}")
                ngx.say("X-Bar: {" .. tostring(headers["X-Bar"]) .. "}")
            }
        }
    }
}
--- config
    location = /t {

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_header("X-Foo", "")

        }

        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
X-Foo: {}
X-Bar: {nil}
--- no_error_log
[error]
