require 'thread'

module DJS
  TYPE_HANDSHAKE = 0
  TYPE_CONNECT   = 1
  TYPE_RESPONSE  = 2
  TYPE_MESSAGE   = 3
  TYPE_CLOSE     = 4
  TYPE_CALLBACK  = 5
  TYPE_RECONNECT = 6
  TYPE_RPC       = 7

  SPECIAL_METHODS = [:childNodes]

  TERMINAL = "\t"

  class DJSError < RuntimeError; end
  class DJSBadRequestError < DJSError; end

  def self.start(klass = DJSConnection, opts = {})
    @@server = DJSServer.new(klass, opts)
    DJSConnections.server = @@server
  end

  def self.stop
    @@server.stop
  end

  def self.response(request)
    if request =~ /\A(\d)\t(\d+)\t(.*)\z/
      case $1.to_i
      when TYPE_HANDSHAKE
        response = @@server.handshake
      when TYPE_CONNECT
        response = @@server.connect($2.to_i)
      when TYPE_RESPONSE
        response = @@server.response($2.to_i, $3)
      when TYPE_MESSAGE
        # TODO
      when TYPE_CLOSE
        # TODO
      when TYPE_CALLBACK
        response = @@server.callback($2.to_i, *$3.split("\t"))
      when TYPE_RECONNECT
        response = @@server.reconnect($2.to_i)
      when TYPE_RPC
        response = @@server.rpc($2.to_i)
      else

      end
    else
      Thread.new do
        onerror DJSBadRequestError.new
      end
      response = TERMINAL
    end

    return response.to_s
  end

  def self.connections
    @@server.djs_connections
  end

  def self.add_task(conn, name, *args)
    @@server.add_task(conn, name, *args)
  end

  class DJSConnections

    def self.server=(server)
      @@server = server
    end

    def initialize(connections)
      @connections = connections
    end

    def [](pattern)
      if pattern == "*"
        return self
      end
      DJSConnections.new(Hash.new)
    end

    def method_missing(name, *args)
      @connections.values.each { |conn|
        next unless conn.type == :main
        rpc_conn = @@server.create_rpc_connection(conn.cid, name, args)
        prx = DJSRpcProxyObject.new(rpc_conn)
        conn.request.push "0\t" + prx.__json
      }
    end
  end

  class DJSServer
    RECONNECT = ""
    DEFAULT_OPTS = {
      :buff_size => 200
    }

    def initialize(klass = DJSConnection, opts = {})
      @klass = klass
      @opts = DEFAULT_OPTS.merge(opts)

      @connections = Hash.new
      @djs_connections = DJSConnections.new(@connections)
      @tasks = Queue.new
      @group = ThreadGroup.new
      @thread = run
      @group.add @thread
    end
    attr_reader :connections, :djs_connections

    def run
      Thread.start do
        begin
          while true
            main_loop
          end
        ensure
          # TODO kill thread
        end
      end
    end

    def main_loop
      Thread.start(@tasks.pop) do |task|
        conn = task[0]
        name = task[1]
        args = task[2]
        fiber = Fiber.new do
          if args
            conn.send(name, *args)
          else
            conn.send(name)
          end
          conn.add_proxy(nil, true)
          TERMINAL
        end
        req = fiber.resume
        if req == TERMINAL
          if conn.type == :main
            conn.request.push RECONNECT
          else
            @connections.delete(conn.__id__)
            conn.request.push TERMINAL
            return
          end
        else
          conn.request.push req
        end
        while rsp = conn.response.pop
          req = fiber.resume(rsp)
          if req == TERMINAL
            if conn.type == :main
              conn.request.push RECONNECT
            else
              @connections.delete(conn.__id__)
              conn.request.push TERMINAL
              return
            end
          else
            conn.request.push req
          end
        end
      end
    end

    def stop
      @group.list.each { |thread|
        thread.kill
      }
    end

    def handshake
      @group.add Thread.current
      conn = @klass.new(:main, 0, @opts)
      @connections[conn.__id__] = conn
      return conn.__id__.to_s
    end

    def connect(id)
      @group.add Thread.current
      conn = @connections[id]
      add_task conn, :on_open
      req = conn.request.pop
      return req
    end

    def reconnect(id)
      @group.add Thread.current
      conn = @connections[id]
      req = conn.request.pop
      return req
    end

    def response(id, rsp)
      @group.add Thread.current
      conn = @connections[id]
      conn.response.push rsp
      req = conn.request.pop
      return req
    end

    def callback(cid, method, event_id)
      @group.add Thread.current
      conn = @klass.new(:callback, cid, @opts)
      @connections[conn.__id__] = conn
      add_task conn, :on_callback, method, event_id
      req = conn.request.pop
      return conn.__id__.to_s + "\t" + req
    end

    def rpc(id)
      @group.add Thread.current
      conn = @connections[id]
      add_task conn, conn.rpc[0], *conn.rpc[1]
      req = conn.request.pop
      return req
    end

    def add_task(conn, name, *args)
      @tasks.push [conn, name, args]
    end

    def create_rpc_connection(cid, name, args)
      conn = @klass.new(:rpc, cid, @opts)
      @connections[conn.__id__] = conn
      conn.set_rpc(name, args)
      return conn
    end
  end

  class DJSConnection
    SEP = "\t"

    def initialize(type, cid = 0, opts = {})
      @type = type
      if @type == :main
        @cid = self.__id__
      else
        @cid = cid
      end
      @opts = opts
      @request = Queue.new
      @response = Queue.new
      @proxies = Hash.new
      @proxy_ids = Array.new
      @mutex = Mutex.new
      @registered_function = Array.new
    end

    attr_accessor :type, :request, :response, :proxies
    attr_reader :cid, :registered_function

    def set_rpc(name, args)
      @rpc = [name, args]
    end

    def rpc
      @rpc
    end

    def add_proxy(proxy, flush_now = false)
      if @register
        @register << SEP << proxy.__json if proxy
      else
        @mutex.synchronize {
          if proxy
            @proxy_ids << proxy.__id__
            @proxies[proxy.__id__] = proxy
          end
          # TODO length
          if flush_now || @proxy_ids.length == @opts[:buff_size]
            flush
          end
        }
      end
    end

    def sync
      add_proxy(nil, true)
    end

    def flush
      if @proxy_ids.empty?
        return
      end

      error = nil

      json = "0\t"
      @proxy_ids.each { |id|
        json << @proxies[id].__json << SEP
      }
      json[-1] = ""
      rsp = Fiber.yield(json)
      while rsp != '{}'
        info = eval(rsp)

        if info.key?('type')
          result = info['type'].send(info['content'], *info['args'])
          proxy = @proxies[info['id']]
          proxy = @proxies[proxy.info[:id]]
          proxy.origin = result
          proxy.solved = true

          json = "1\t{\"id\":" + DJS.to_json(info["id"]) + ",\"origin\":" + DJS.to_json(result) + "}"
          rsp = Fiber.yield(json)
        elsif info.key?('error')
          error = @proxies[info['id']].exe_info + ": " + info['error']
          break
        else
          info.each { |key, value|
            if @proxies.key?(key)
              @proxies[key].origin = value
              @proxies[key].solved = true
            end
          }
          break
        end
      end

      @proxies.clear
      @proxy_ids.clear

      if error
        on_error(error)
      end
    end

    def on_callback(method_name, event_id)
      method = self.method(method_name)
      if method.arity == 1
        event = DJSEventProxyObject.new(self, event_id)
        method.call(event)
      else
        method.call
      end
    end

    # Event handler
    def on_open

    end

    def on_close

    end

    def on_message(msg)

    end

    def on_error(err)

    end

    # Root Javascript Object
    def window
      DJSProxyObject.new(self, {:type => :window})
    end

    def register_function(name)
      sync
      method = self.method(name)
      @register = '2' << SEP << name.to_s << ",0"
      if method.arity < 0
        raise "Optional arguments is not supported!"
      end
      arguments = []
      method.arity.times { |i|
        arguments << DJSArgument.new(self, "ext[#{i}]")
      }
      method.call(*arguments)
      Fiber.yield(@register)
      @register = nil
      @registered_function << name
    end

    def method_missing(name, *args, &block)
      window.method_missing(name, *args)
    end
  end

  class DJSProxyObject
    def initialize(conn, info, exe_info = '')
      @conn = conn
      @info = info
      @origin = nil
      @solved = false
      @info[:id] = __id__
      @info[:cid] = conn.cid
      @exe_info = exe_info
    end

    attr_accessor :origin, :solved, :info, :conn
    attr_reader :exe_info

    def method_missing(name, *args, &block)
      if @solved
        return @origin.send(name, *args, &block)
      end

      if block
        @conn.add_proxy(nil, true)
        return @origin.send(name, *args, &block)
      end

#      if @conn.registered_function.include?(name)
#        proxy = DJSProxyObject.new(@conn, {:type => "window", :content => "FUNCS[#{name}]", :args => args}, caller[0])
#        @conn.add_proxy proxy
#        return proxy
#      end

      if name.to_s =~ /^_[A-Z]/ && args.size == 0
        return DJSClassProxyObject.new(@conn, name, caller[0])
      end

      if name.to_s =~ /^.*=$/ && args && Symbol === args[0]
        name = "{}" + name.to_s[/[^=]+/]
      end

      if SPECIAL_METHODS.include?(name)
        proxy = DJSProxyObject.new(@conn, {:type => self, :content => name, :args => args, :ex => 'object'}, caller[0])
      else
        proxy = DJSProxyObject.new(@conn, {:type => self, :content => name, :args => args}, caller[0])
      end
      @conn.add_proxy proxy
      return proxy
    end

    def [](key)
      proxy = DJSProxyObject.new(@conn, {:type => self, :content => :[], :args => [key]}, caller[0])
      @conn.add_proxy proxy
      return proxy
    end

    def []=(key, value)
      proxy = DJSProxyObject.new(@conn, {:type => self, :content => :[]=, :args => [key, value]}, caller[0])
      @conn.add_proxy proxy
      return proxy
    end

    def sync
      return @origin if @solved
      @conn.add_proxy(nil, true)
      return @solved ? @origin : self
    end

    def __json
      DJS.to_json @info
    end

    def __to_s
      #TODO refs
      if DJSProxyObject === @info[:type]
        return "REFS[" + __id__.to_s + "].origin"
      else
        return @info[:type].to_s
      end
    end
  end

  class DJSEventProxyObject < DJSProxyObject
    def initialize(conn, event_id)
      super(conn, {:type => "EVENTS[#{event_id}]"})
    end
  end

  class DJSRpcProxyObject < DJSProxyObject
    def initialize(conn)
      super(conn, {:type => 'rpc', :content => conn.__id__})
    end
  end

  class DJSArgument < DJSProxyObject
    def initialize(conn, name)
      @name = name
      super(conn, {:type => self})
    end

    def __to_s
      @name
    end
  end

  class DJSClassProxyObject < DJSProxyObject
    def initialize(conn, name, caller)
      @name = name[1, name.length]
      super(conn, {:type => self}, caller)
    end

    def new(*args)
      proxy = DJSProxyObject.new(@conn, {:type => 'new', :content => @name, :args => args}, caller[0])
      @conn.add_proxy proxy
      proxy.info[:type] = self
      return proxy
    end
  end

  def self.to_json(obj)
    case obj
    when Hash
      json = '{'
      obj.each { |key, value|
        json << '"' << key.to_s << '":' << to_json(value) << ','
      }
      if (json.length > 1)
        json[-1] = '}'
      else
        json << '}'
      end
      return json
    when Array
      json = '['
      obj.each { |item|
        json << to_json(item) << ','
      }
      if (json.length > 1)
        json[-1] = ']'
      else
        json << ']'
      end
      return json
    when DJSProxyObject
      return obj.__to_s
    when Numeric
      return obj.to_s
    when String
      return '"' + obj.gsub('"', '\\"') + '"'
    when TrueClass, FalseClass
      return obj.to_s
    else
      return '"' + obj.to_s + '"'
    end
  end
end
