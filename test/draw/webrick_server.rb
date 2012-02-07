require 'webrick'
require './draw'

class WebrickServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_POST(req, res)
    res['Content-Type'] = 'text/plain'
    res.body = DJS.response(req.body)
  end
end

server = WEBrick::HTTPServer.new({
  :DocumentRoot => File.dirname(__FILE__) + '/../../',
  :BindAddress => 'localhost',
  :Port => 8080})
server.mount('/djs', WebrickServlet)
trap('INT') {
    DJS.stop
    server.shutdown
}
DJS.start(LogoConnection)
server.start

