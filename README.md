# RESTR

Provide a simple RESTful interface to R, with results returned as a JSON-encoded string.

The server is a Ruby Rack application.

## Requirements

For Ruby, you will need the following gems:

- `rack`
- `rack-cors`

For R, you will need the following package:

- `rjson`

Additionally, the R binary should be in your path so that the Ruby script can find it.

## Usage

The url is of the form:

    http://hostname:port/namespace/function/positional/arguments?named=arguments

For example, assuming you have the base namespace allowed:

    http://localhost:6312/base/c/1/2/3

this will return `[1,2,3]`, i.e. is equivalent to the result of `base::c(1,2,3)` converted to JSON.

## Details

The Rack application keeps around a pool of R processes that are waiting on a JSON-encoded command to come in on a pipe.  Once the Rack app receives a request, it converts it to a JSON-encoded command and sends it along that pipe, and then waits for the process to terminate.  The R process runs the requested function, encodes the output as JSON (via `rjson`), and delivers that string to another pipe, and exits.  The Rack app pulls the JSON string from that pipe, and delivers it to the client.  Meanwhile, another thread puts a new R process in the pool to replace the exited one.

The reasoning behind having a pool of waiting R processes is so that the client doesn't need to wait for the R process to start up.

The pipe-based communication is achieved using `IO.pipe` on the Ruby side, and `file('/dev/sd/[0-9]+', raw=T)` on the R side.
