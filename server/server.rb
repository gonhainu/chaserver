require 'socket'
require 'net/http'
require 'json'
require 'uri'

class Player
  MAX_NAME_LEN = 32
  CONNECT_ABLE_PORT = [40000, 50000]

  attr_reader :sock, :side, :port, :host, :regx, :conn, :addr
  def initialize(side, port, host)
    @sock = TCPServer.open(host, port)
    @sock.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
    @sock.listen(1)
    @side = side
    @port = port
    @host = host
    @regx = "[wlsp][rlud]"
  end

  def accept()
    @conn = @sock.accept 
    @addr = Socket.unpack_sockaddr_in(@sock.getsockname)
  end

  def nameget()
    name = @conn.recv(MAX_NAME_LEN).strip
    CONNECT_ABLE_PORT.map{|p|
      if @port == p
        name = name.force_encoding('UTF-8')
      end
    }
    if "" == name
      if @side == 'C' 
        @name = 'COOL'
      else 
        @name = 'HOT'
      end
    else
      @name = name
    end
  end

  def gr()
    str = __recv()
    unless "gr" == str
      return false
    end
    return true
  end

  def cmd()
    str = __recv()
    unless str.match(@regx)
      return nil
    end
    return true
  end

  def __recv()
    str = @conn.recv(4)
    if str.length < 2
      return nil
    end
    return str[0...2]
  end
end

class Server
  def initialize(id)
    @id = id
  end

  def prepare(url, name, c_port, h_port, host)
    @url = url
    __http('POST', 'serverHello', {name: name})
    @cool = Player.new('C', c_port, host)
    @hot = Player.new('H', h_port, host)

    [@cool, @hot].map{|p|
      p.accept
      __http('POST', 'clientHello', {side: p.side, addr: p.addr[1], port: p.addr[0]})
    }
    [@cool, @hot].map{|p|
      @now = p
      p.nameget
      __http('POST', 'clientHello', {side: p.side, name: name})
    }
    while __http('GET', 'isStart')['flg'] != 1 do
        sleep(1)
    end
    __http('POST', 'serverStart')
  end

  def zoi()
    cool_end = false
    hot_end = false
    interval = 1

    while (true == cool_end and true == hot_end) do
      [@cool, @hot].map{|p|
        next if true == cool_end and p == @cool
        next if true == hot_end and p == @hot
        @now = p 
        p.conn.sendmsg("@\r\n")

        raise SyntaxError unless p.gr
        unless __exchange(p, 'gr')    
          if p == @cool
            cool_end = true
          else
            hot_end = true
          end
          break
        end

        cmd = p.cmd
        raise SyntaxError if cmd.nil?
        interval *= 0.99
        interval = 0.1 if interval < 0.1
        sleep(interval)
        run_flg = __exchange(p, cmd)
        unless run_flg
          if p == @cool
            cool_end = true
          else
            hot_end = true
          end
          break
        end
        
        raise SyntaxError unless p.conn.recv(3) == "#\r\n"
      }
    end
  end

  def __exchange(p, cmd)
    recv = __http('POST', 'clientRequest', {side: p.side, cmd: cmd})['result']
    raise SyntaxError unless recv.length == 10
    p.conn.sendmsg(recv + "\r\n")
    return recv[0] == '1'
  end

  def __http(method, path, query=nil)
    url = URI.parse("#{@url}#{path}")
    query = {} if query.nil?
    query[:id] = @id

    if 'POST' == method
      r = Net::HTTP.post_form(url, query)
    else
      r = Net::HTTP.get(url, query)
    end
    res = JSON.parse(r.body)
    if 'serverHello' == path or 'serverDisconnect' == path 
      puts "#{path}:#{query[:id]}"
    elsif 'clientHello' == path and query.has_key?(:name)
      puts "#{path}:#{query[:side]}:#{query[:name]}"
    elsif 'clientRequest' == path
      puts "#{path}:#{query[:side]}:#{query[:cmd]}:#{ret[:result]}"
    end
    return res
  end

  def error(err)
    STDERR.puts err
    __http('POST', 'clientError', {side: @now.side, msg: err})
  end

  def cleanup()
    __http('POST', 'serverDisconnect')
    
    [@cool, @hot].map{|p| 
      p.sock.close() unless p.nil? or p.conn.nil? 
    }
  end
end

URL = 'http://127.0.0.1:3000/'
NAME = '練習場1'
#ID = ''.join([random.choice(string.ascii + string.digits) for i in range(16)])
ID = 'testserver'
  
HOST = '0.0.0.0'
COOL_PORT = 40000
HOT_PORT = 50000

while true do
  game = Server.new(ID)

  begin
    game.prepare(URL, NAME, COOL_PORT, HOT_PORT, HOST)
    game.zoi()
  rescue SocketError => e
    game.error('Socket Error')
  rescue SyntaxError => e
    game.error('Command Error')
  else
    game.error('Unknown Error')
  ensure
    game.cleanup()
    sleep(5)
  end
end
