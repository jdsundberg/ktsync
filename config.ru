require 'bundler'

Bundler.require

require './lib/ktsync'
run Sinatra::Application
