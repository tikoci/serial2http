# serial2http
**_RouterOS container that proxies serial port via HTTP using TCP serial (RFC-2217)_**

## Problem

RouterOS supports serial via `/ports`, including serial devices via USB or actual serial ports on the device. While RouterOS allows serial to IP via `/ports/remote-access`, e.g.

```
/port remote-access add port=serial0 protocol=rfc2217 tcp-port=22171
```

But what RouterOS does not have an RFC-2217 client in the CLI and/or RouterOS scripts. e.g. SENDING new serial data to a connected (or remote) serial device – not just exposing a physical port as IP port. 

**Serial ports on RouterOS**

See: https://help.mikrotik.com/docs/display/ROS/Ports

See also: http://forum.mikrotik.com/viewtopic.php?p=138054&hilit=rfc2217#p138054



## Using `at-chat` to talk to serial

One workaround is to create a `/interface/ppp-client` with port set to the serial devices, then commands can be issued via:
```
/ppp-out1 at-chat input="ATX"
```
 But that only works with serial devices that have an AT command set.  But the "trick" doesn't work if "OK" is not the response.  While it be better if "at-chat" was more flexible & perhaps an option on /port/remote-access to inject data on the shared ports.  It is not today.
 
 
 
## Using HTTP via a container to "chat" with TCP-enabled serial ports

> **Important:** since /container does NOT have direct access to the serial ports.  **Using /ports/remote-access is required to use this container, include any directly attached serial device** — because only IP is allowed between container and RouterOS, not `/dev` devices (tty, usb, etc.).

RouterOS does a `/tool/fetch`, but obviously that doesn't work with serial data (or the remote-access ports either).  But a container can do whatever userland stuff (e.g. no USB/devices).  So this one has a small python script that listens for incoming `HTTP POST` request, sends via IP-based serial port (e.g. a `/port/remote-access`), and then returns the response from the serial device in the HTTP response as plain text. 

 So with the "serial2http" container, the following sends "my-data-to-go-to-serial" to a IP-wrapped serial device, and the output is available in CLI:
```
/tool/fetch url=http://172.22.17.1 method=post http-data="my-data-to-go-to-serial" output=user
```
(or in scripting by storing the result of `/tool/fetch` in a `:global` variable by adding an `as-value` above)

## Uses Python's PySerial library
 Python's pySerial library is used to connect to any serial port specifed in the containers `envs` for `SERIALURL`.  PySerial uses a URL-scheme to describe the host, so adjusting the `envs` can change to specific serial deviced used to communicate. 
 ```
 key="SERIALURL" value="rfc2217://172.22.17.254:22171?ign_set_control&logging=debug&timeout=3"
 ```

Critical to serial2http container is the PySerial's URL above.  Please see: https://pyserial.readthedocs.io/en/latest/url_handlers.html for details on what can be set in SERIALURL envs above.  
> e.g. if you set `raw` as `type` for an item in `/ports/remote-access`, then use the `socket://` in `SERIALURL`.  
 
 Check out the rest of PySerial if you want to extend or use this container.  This container only does a very basic thing: looks for a "\n" to know when to return a response.  
 

## Installing `serial2http` container on RouterOS

Create a new container from tag `ghcr.io/tikoci/serial2http:main` with the `https://ghcr.io` as the registry-url (in `/container/config`).  Or build it yourself (see below). 

Either case, the container uses the following environment variables to control it's actions:

```
/container/envs {
    # HTTP port the container listens for commands on...
    add name="$containertag" key="PORT" value=80 
    # PySerial "URL" to use to connect to serial device via RFC2217
    add name="$containertag" key="SERIALURL" value="rfc2217://172.22.17.254:22171?ign_set_control&logging=debug&timeout=3"
    # while most options can be set in the pyserial's url, BAUDRATE must be explicit 
    add name="$containertag" key="BAUDRATE" value=115200
}
```

## Building the image locally instead

You'll need the Docker installed first.  The `git clone` or download the source to a directory on your desktop, then run standard `docker build`:
```
docker build --platform linux/arm/v7 -t serial2http .     
docker save serial2http > ../serial2http.tar  
```
The .tar file will be in the parent directory.  You can copy and install on your router, using the envs discussed above to control.

## Security Considerations

Both sides of the proxy use insecured IP traffic, so you'd want to think about how best to use RouterOS firewall to best protect both:
* port used in `/tool/remote-access` used to expose a serial port to TCP
* container's subnet which listens on `HTTP` on port 80 for commands to send

The specific firewall configuration needed will depend on your usage – but should not be ignored here.


## Disclaimer
Not the python nor Docker/OCI expert – only used Python since PySerial has very rich serial support – so feel free to report any issues in this implementation.  
