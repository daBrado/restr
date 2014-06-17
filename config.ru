require 'logger'
require_relative 'config'
require_relative 'restr'
require 'rubygems'
require 'bundler/setup'
run RESTR.new(R_CMD, R_NAMESPACES, R_POOL_SIZE, LOG)
