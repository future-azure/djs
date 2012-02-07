require 'webrick'
require './peg_solitaire'

class WebrickServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_POST(req, res)
    res['Content-Type'] = 'text/plain'
    res.body = DJS.response(req.body)
  end
end

server = WEBrick::HTTPServer.new({
  :DocumentRoot => File.dirname(__FILE__) + '/../../',
  :Port => 8080,
  :BindAddress => 'localhost'})
server.mount('/djs', WebrickServlet)
trap('INT') {
  DJS.stop
  server.shutdown
}
DJS.start(PegSolitaire)
server.start

