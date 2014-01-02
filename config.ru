R_NAMESPACES = []  # Empty gives access to *all* namespaces

require 'rubygems'
require 'bundler/setup'
require './restr'
run RESTR.new(R_NAMESPACES)
