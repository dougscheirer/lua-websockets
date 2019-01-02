local websocket = require'websocket'
local socket = require'socket'
local client = require'websocket.client'
local ev = require'ev'
local frame = require'websocket.frame'
local port = (os.getenv('LUAWS_WSTEST_PORT') or 11000) + 1
local req_ws = ' (requires external secure websocket server @port '..port..')'
local url = 'wss://127.0.0.1:'..port

setloop('ev')

-- a lot of this is copy/pasta from client_ev_spec.lua but with ssl_params
describe(
  'The client (ev) wss module',
  function()
    local wsc

    local ssl_params = {mode='client',protocol = "any",verify = "none",options = "all"}

    local random_text = function(len)
      local chars = {}
      for i=1,len do
        chars[i] = string.char(math.random(33,126))
      end
      return table.concat(chars)
    end

    it(
      'exposes the correct interface',
      function()
        assert.is_table(client)
        assert.is_function(client.ev)
      end)

    it(
      'can be constructed',
      function()
        wsc = client.ev()
      end)
    
    it(
      'refuses to connect for insecure ws'..req_ws,
      function(done)
        settimeout(3)
        wsc:on_error(async(function(ws,err)
              assert.is_equal(ws,wsc)
              -- for wss connections, the response is failure to establish the connection
              assert.is_equal(err,'accept failed')
              ws:on_error()
              -- make sure to close the connection, connection errors don't do that
              -- automatically and future tests want a non-CONNECTING state
              ws:close()
              done()
          end))
        wsc:connect('ws://127.0.0.1:'..port,'echo-protocol',ssl_params)
      end)
    
    it(
      'can connect and calls on_open'..req_ws,
      function(done)
        settimeout(10)
        assert(wsc:cur_state() == 'CLOSED','unexpected state:'..wsc:cur_state())
        wsc:on_open(async(function(ws,protocol,headers)
              assert.is_equal(ws,wsc)
              assert.is_equal(protocol,'echo-protocol')
              assert.is.truthy(headers['sec-websocket-accept'])
              assert.is.truthy(headers['sec-websocket-protocol'])
              done()
          end))
        wsc:connect(url,'echo-protocol',ssl_params)
      end)
    it(
      'calls on_error if already connected'..req_ws,
      function(done)
        assert(wsc:cur_state() == 'OPEN','unexpected state:'..wsc:cur_state())
        settimeout(3)
        wsc:on_error(async(function(ws,err)
              assert.is_equal(ws,wsc)
              assert.is_equal(err,'wrong state')
              ws:on_error()
              ws:on_close(function() done() end)
              ws:close()
          end))
        wsc:connect(url,'echo-protocol',ssl_params)
      end)
    it(
      'calls on_error on bad protocol'..req_ws,
      function(done)
        assert(wsc:cur_state() == 'CLOSED','unexpected state:'..wsc:cur_state())
        settimeout(3)
        wsc:on_error(async(function(ws,err)
              assert.is_equal(ws,wsc)
              assert.is_equal(err,'bad protocol')
              ws:on_error()
              done()
          end))
        wsc:connect('ws2://127.0.0.1:'..port,'echo-protocol',ssl_params)
      end)
    -- TODO: set up a HTTPS server with the associated pem files to run on port + 20
    pending(
      'can parse HTTP request header byte per byte',
      function(done)
        assert(wsc:cur_state() == 'CLOSED','unexpected state:'..wsc:cur_state())
        local resp = {
          'HTTP/1.1 101 Switching Protocols',
          'Upgrade: websocket',
          'Connection: Upgrade',
          'Sec-Websocket-Accept: e2123as3',
          'Sec-Websocket-Protocol: chat',
          '\r\n'
        }
        resp = table.concat(resp,'\r\n')
        assert.is_equal(resp:sub(#resp-3),'\r\n\r\n')
        local socket = require'socket'
        local http_serv = socket.bind('*',port + 20)
        local http_con
        wsc:on_error(async(function(ws,err)
              assert.is_equal(err,'accept failed')
              ws:close()
              http_serv:close()
              http_con:close()
              done()
          end))
        wsc:on_open(async(function()
              assert.is_nil('should never happen')
          end))
        wsc:connect('wss://127.0.0.1:'..(port+20),'chat',ssl_params)
        http_con = http_serv:accept()
        local i = 1
        ev.Timer.new(function(loop,timer)
            if i <= #resp then
              local byte = resp:sub(i,i)
              http_con:send(byte)
              i = i + 1
            else
              timer:stop(loop)
            end
          end,0.0001,0.0001):start(ev.Loop.default)
      end)
    -- TODO: set up a HTTPS server with the associated pem files to run on port + 20
    pending(
      'properly calls on_error if socket error on handshake occurs',
      function(done)
        assert(wsc:cur_state() == 'CLOSED','unexpected state:'..wsc:cur_state())
        local resp = {
          'HTTP/1.1 101 Switching Protocols',
          'Upgrade: websocket',
          'Connection: Upgrade',
        }
        resp = table.concat(resp,'\r\n')
        local socket = require'socket'
        local http_serv = socket.bind('*',port + 20)
        local http_con
        wsc:on_error(async(function(ws,err)
              assert.is_equal(err,'accept failed')
              ws:on_close(function() done() end)
              ws:close()
              http_serv:close()
              http_con:close()
          end))
        wsc:on_open(async(function()
              assert.is_nil('should never happen')
          end))
        wsc:connect('wss://127.0.0.1:'..(port+20),'chat',ssl_params)
        http_con = http_serv:accept()
        local i = 1
        ev.Timer.new(function(loop,timer)
            if i <= #resp then
              local byte = resp:sub(i,i)
              http_con:send(byte)
              i = i + 1
            else
              timer:stop(loop)
              http_con:close()
            end
          end,0.0001,0.0001):start(ev.Loop.default)
      end)
    it(
      'can open and close immediatly (in CLOSING state)'..req_ws,
      function(done)
        assert(wsc:cur_state() == 'CLOSED','unexpected state:'..wsc:cur_state())
        wsc:on_error(async(function(_,err)
              assert.is_nil(err or 'should never happen')
          end))
        wsc:on_close(function(_,was_clean,code)
            assert.is_false(was_clean)
            assert.is_equal(code,1006)
            done()
          end)
        wsc:connect(url,'echo-protocol',ssl_params)
        wsc:close()
      end)
    it(
      'socket err gets forwarded to on_error',
      function(done)
        assert(wsc:cur_state() == 'CLOSED','unexpected state:'..wsc:cur_state())
        settimeout(6.0)
        wsc:on_error(async(function(ws,err)
              assert.is_same(ws,wsc)
              if socket.tcp6 then
                assert.is_equal(err, 'host or service not provided, or not known')
              else
                assert.is_equal(err,'host not found')
              end
              --              wsc:close()
              done()
          end))
        wsc:on_close(async(function()
              assert.is_nil(err or 'should never happen')
          end))
        wsc:connect('wss://does_not_exist','echo-protocol',ssl_params)
      end)
    it(
      'can send and receive data'..req_ws,
      function(done)
        assert(wsc:cur_state() == 'CLOSED','unexpected state:'..wsc:cur_state())
        wsc = client.ev()
	      settimeout(6.0)
        assert.is_function(wsc.send)
        wsc:on_error(async(function(ws,err)
        end
        ))
        wsc:on_close(async(function(ws,err)
        end
        ))
        wsc:on_message(
          async(
            function(ws,message,opcode)
              assert.is_equal(ws,wsc)
              assert.is_same(message,'Hello again')
              assert.is_same(opcode,frame.TEXT)
              done()
          end))
        wsc:on_open(function()
            wsc:send('Hello again')
          end)
        wsc:connect(url,'echo-protocol',ssl_params)
      end)
    it(
      'can send and receive data 127 byte messages'..req_ws,
      function(done)
        assert(wsc:cur_state() == 'OPEN','unexpected state:'..wsc:cur_state())
        settimeout(6.0)
        local msg = random_text(127)
        wsc:on_message(
          async(
            function(ws,message,opcode)
              assert.is_same(#msg,#message)
              assert.is_same(msg,message)
              assert.is_same(opcode,frame.TEXT)
              done()
          end))
        wsc:send(msg)
      end)

    it(
      'can send and receive data 0xffff-1 byte messages'..req_ws,
      function(done)
        assert(wsc:cur_state() == 'OPEN','unexpected state:'..wsc:cur_state())
        settimeout(10.0)
        local msg = random_text(0xffff-1)
        wsc:on_message(
          async(
            function(ws,message,opcode)
              assert.is_same(#msg,#message)
              assert.is_same(msg,message)
              assert.is_same(opcode,frame.TEXT)
              done()
          end))
        wsc:send(msg)
      end)

    it(
      'can send and receive data 0xffff+1 byte messages'..req_ws,
      function(done)
        assert(wsc:cur_state() == 'OPEN','unexpected state:'..wsc:cur_state())
        settimeout(10.0)
        local msg = random_text(0xffff+1)
        wsc:on_message(
          async(
            function(ws,message,opcode)
              assert.is_same(#msg,#message)
              assert.is_same(msg,message)
              assert.is_same(opcode,frame.TEXT)
              done()
          end))
        wsc:send(msg)
      end)
    it(
      'closes cleanly'..req_ws,
      function(done)
        assert(wsc:cur_state() == 'OPEN','unexpected state:'..wsc:cur_state())
        settimeout(6.0)
        wsc:on_close(async(function(_,was_clean,code,reason)
              assert.is_true(was_clean)
              assert.is_true(code >= 1000)
              assert.is_string(reason)
              done()
          end))
        wsc:close()
      end)
    it(
      'echoing 10 messages works'..req_ws,
      function(done)
        assert(wsc:cur_state() == 'CLOSED','unexpected state:'..wsc:cur_state())
        settimeout(3.0)
        wsc:on_error(async(function(_,err)
              assert.is_nil(err or 'should never happen')
          end))
        wsc:on_close(async(function()
              assert.is_nil('should not happen yet')
          end))
        wsc:on_message(async(function()
              assert.is_nil('should not happen yet')
          end))
        wsc:on_open(async(function(ws)
              assert.is_same(ws,wsc)
              local count = 0
              local msg = 'Hello websockets'
              wsc:on_message(async(function(ws,message,opcode)
                    count = count + 1
                    assert.is_same(ws,wsc)
                    assert.is_equal(message,msg..count)
                    assert.is_equal(opcode,websocket.TEXT)
                    if count == 10 then
                      ws:on_close(async(function(_,was_clean,opcode,reason)
                            assert.is_true(was_clean)
                            assert.is_true(opcode >= 1000)
                            done()
                        end))
                      ws:close()
                    end
                end))

              for i=1,10 do
                wsc:send(msg..i)
              end
          end))
        wsc:connect(url,'echo-protocol',ssl_params)
      end)
  end)
