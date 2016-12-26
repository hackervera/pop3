require "./pop3/*"
require "socket"
require "http/client"
require "json"

class Matrix
  getter :access_token
  record Message, sender : String, room_id : String, event_id : String, body : String

  MATRIX_HOST =
    begin
      ENV["MATRIX_HOST"]
    rescue
      "matrix.org"
    end

  ROOM_ID =
    begin
      ENV["MATRIX_ROOM"]
    rescue
      "!cURbafjkfsMDVwdRDQ:matrix.org"
    end

  USER = ENV["MATRIX_USER"]
  PASS = ENV["MATRIX_PASS"]

  def initialize(@access_token = "")
    response = HTTP::Client.post "https://#{MATRIX_HOST}/_matrix/client/r0/login", body: {"type" => "m.login.password", "user" => USER, "password" => PASS}.to_json
    # puts response.inspect
    @access_token = JSON.parse(response.body)["access_token"].to_s
  end

  def get_messages
    response = HTTP::Client.get "https://#{MATRIX_HOST}/_matrix/client/r0/sync?access_token=#{@access_token}"
    JSON.parse(response.body)["rooms"]["join"][ROOM_ID]["timeline"]["events"].map do |event|
      Message.new event["sender"].to_s, ROOM_ID, event["event_id"].to_s, event["content"]["body"].to_s
    end
  end
end

module Pop3
  server = TCPServer.new(110)
  matrix = Matrix.new
  msg_hsh = {} of Int32 => String

  # puts matrix.access_token
  loop do
    server.accept do |socket|
      puts "Incoming connection"

      messages = matrix.get_messages
      messages.each_with_index do |message, index|
        str =
          <<-EMAIL
From: #{message.sender}
Event_ID: #{message.event_id}
Room_ID: #{message.room_id}
#{message.body}
EMAIL
        msg_hsh[index + 1] = str
      end
      # puts messages
      # sleep
      socket.puts "+OK POP3 server ready <999@matrix.org>\r"
      begin
        loop do
          command = socket.gets
          puts command
          case command
          when /RETR/
            command =~ /RETR (\d+)/
            num = $1.to_i
            puts num
            puts "sending"
            message = msg_hsh[num]
            socket.puts "+OK #{message.bytesize} octets\r"
            socket.puts "#{message}"
            socket.puts ".\r"
          when /LIST/
            socket.puts "+OK\r"
            msg_hsh.each do |num, body|
              socket.puts "#{num} #{body.bytesize}\r"
            end
            socket.puts ".\r"
          when /STAT/
            total = msg_hsh.values.reduce(0) { |sum, message| sum + message.bytesize }
            socket.puts "+OK #{msg_hsh.size} #{total}\r"
          when /APOP/
            socket.puts "+OK\r"
          when "CAPA"
            socket.puts "+OK\r"
            socket.puts ".\r"
          else
            # socket.puts "+OK\r"
          end
        end
      rescue e
        puts e
      end
    end
  end
  # TODO Put your code here
end
