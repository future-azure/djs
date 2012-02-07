require 'sinatra'
require './peg_solitaire'

set :port, 8080
set :public_folder, File.dirname(__FILE__) + '/../../'

post '/djs' do
  DJS.response request.body.read
end

DJS.start(PegSolitaire)
