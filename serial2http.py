#!/usr/bin/env python3
import serial
import io
import os
from http.server import BaseHTTPRequestHandler

defserialurl= "rfc2217://172.22.17.254:22171?ign_set_control&logging=debug&timeout=3"
httpport    = os.getenv('PORT', "80")  
serialurl   = os.getenv('SERIALURL', defserialurl) 
baudrate    = os.getenv('BAUDRATE', "115200")
maxtimeout  = os.getenv('TIMEOUT', "5")
print(f'port {httpport} serialurl {serialurl} baudrate {baudrate}', flush=True)

class SerialViaHttpPostHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        # use ENV variables – TODO should use some config class...
        global httpport    
        global defserialurl
        global serialurl   
        global baudrate    

        length = int(self.headers.get('content-length'))
        reqdata = self.rfile.read(length)

        self.send_response(200)
        self.send_header('Content-Type', f'text/plain; charset=unknown-8bit')
        self.end_headers()
        
        with serial.serial_for_url(serialurl, baudrate=int(baudrate), timeout=int(maxtimeout)) as ser:
            try:
                cmdin = reqdata
                print(f"cmdin = {str(cmdin)}({type(cmdin)})", flush=True)
                ser.write(cmdin)
                cmdout = ser.readline() 
                print(f"cmdout = {str(cmdout)}({type(cmdout)})", flush=True)
                self.wfile.write(cmdout)
            finally:
                print("finished", flush=True)
                ser.close()

# when launched as root script, start listening on HTTP
if __name__ == '__main__':
    from http.server import HTTPServer
    server = HTTPServer(('0.0.0.0', int(httpport)), SerialViaHttpPostHandler)
    print(f'HTTP listening on {str(httpport)}')
    server.serve_forever()