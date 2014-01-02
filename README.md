# RESTR

Provide a simple RESTful interface to R, with results returned as a JSON-encoded string.

The server is provided as a Ruby Rack application, and a rackup config.

## Requirements

For Ruby, Bundler will take care of the requirements.

For R, you will need the `rjson` package, and the R binary will need to be in your path.

## Install

To install for deployment, you can do:

    RUBY=/path/to/ruby
    $RUBY/bin/gem install bundler -i vendor/gem -n bin
    bin/bundle install --deployment --binstubs --shebang $RUBY/bin/ruby

Then to run, you can use the installed rackup executable, e.g.:

    bin/rackup -E production -p 6312

## Usage

The url is of the form:

    http://hostname:port/namespace/function/positional/arguments?named=arguments

For example, assuming you have the base namespace allowed:

    http://localhost:6312/base/c/1/2/3

this will return `[1,2,3]`, i.e. is equivalent to the result of `base::c(1,2,3)` converted to JSON.

## Details

The Rack app keeps around a pool of R processes that are waiting on a JSON-encoded command to come in on a pipe.

Once the Rack app receives a request, it converts it to a JSON-encoded command and sends it along the pipe, and then waits for the process to terminate.

The R process decodes the JSON and runs the requested function, encodes the output as JSON, and delivers that string to another pipe, and exits.

The Rack app pulls the JSON string from the return pipe, and delivers it to the client.  Meanwhile, another thread puts a new R process in the pool to replace the exited one.

By having a pool of waiting R processes, the client doesn't need to wait for an R process to start up.

The pipe-based communication is achieved using `IO.pipe` on the Ruby side, and `file('/dev/sd/n', raw=T)` on the R side, where `n` is the file descriptor number found via the Ruby IO object's `fileio` attribute.
