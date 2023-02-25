# `serial2http` — _RouterOS container that proxies serial port via HTTP and TCP_


# Background
##  Problem

RouterOS supports serial via `/ports`, including serial devices via USB or actual serial ports on the device. While RouterOS allows serial to IP via `/ports/remote-access`, e.g.

```
/port remote-access add port=serial0 protocol=rfc2217 tcp-port=22171
```

But what RouterOS does not have an RFC-2217 client in the CLI and/or RouterOS scripts. e.g. SENDING new serial data to a connected (or remote) serial device – not just exposing a physical port as IP port. 

## Using serial ports on RouterOS

See: https://help.mikrotik.com/docs/display/ROS/Ports

See also: http://forum.mikrotik.com/viewtopic.php?p=138054&hilit=rfc2217#p138054



## Using `at-chat` to "talk to serial" method...

One workaround is to create a `/interface/ppp-client` with port set to the serial devices, then commands can be issued via:
```
/ppp-out1 at-chat input="ATX"
```
 But that only works with serial devices that have an AT command set.  But the "trick" doesn't work if "OK" is not the response.  While it be better if "at-chat" was more flexible & perhaps an option on /port/remote-access to inject data on the shared ports.  It is not today.
 
 
 
## Using HTTP via a container to "chat" using this container...

> **Important:** since /container does NOT have direct access to the serial ports.  **Using /ports/remote-access is required to use this container, include any directly attached serial device** — because only IP is allowed between container and RouterOS, not `/dev` devices (tty, usb, etc.).

RouterOS supports `/tool/fetch` for web request, but obviously that doesn't work with serial data (or the remote-access ports either).  But a container can do whatever userland stuff (e.g. no USB/devices) it wants.  So this one has a small python script that listens for incoming `HTTP POST` request, sends via IP-based serial port (e.g. a `/port/remote-access`), and then returns the response from the serial device in the HTTP response as plain text. 

 So with the "serial2http" container installed and running, the following sends "my-data-to-go-to-serial" to a IP-wrapped serial device, and the output is available in CLI:
```
# send text to the serial via the serial2http container

/tool/fetch url=http://172.22.17.1 method=post http-data="my-data-to-go-to-serial" output=user

# output of resulting serial up to newline char (\n) to terminal   
```
(or in scripting by storing the result of `/tool/fetch` in a `:global` variable by adding an `as-value` above)

## Uses Python's PySerial library
 Python's pySerial library is used to connect to any serial port specifed in the containers `envs` for `SERIALURL`.  PySerial uses a URL-scheme to describe the host, so adjusting the `envs` can change to specific serial deviced used to communicate. 
 ```
 key="SERIALURL" value="rfc2217://172.22.17.254:22171?ign_set_control&logging=debug&timeout=3"
 ```

Critical to serial2http container is the PySerial's URL above.  Please see: https://pyserial.readthedocs.io/en/latest/url_handlers.html for details on what can be set in SERIALURL envs above.  
> e.g. if you set `raw` as `type` for an item in `/ports/remote-access`, then use the `socket://` in `SERIALURL`.  
 
 ## Extending to more "serial" use cases
Check out the rest of PySerial if you want to extend or use this container.  This container only does a very basic thing: looks for a "\n" (newline char) in incoming IP serial to know when to return a response via HTTP.  But could easily be adapted to do more serial things in `python` but forking the code here, or modify the script via a mount in RouterOs).
 

# Installing `serial2http` container on RouterOS

## Step 1. Setup environment variable in `/container/envs`
The container uses the environment variables to control it's actions. The follow should be imported onto the Mikrotik so you can edit the settings.  The container internally use the same as defaults.  The following should be done before adding the serial2http container.

```
/container/envs {
    # HTTP port the container listens for commands on...
    add name="serial2http" key="PORT" value=80 
    # PySerial "URL" to serial device via RFC2217 (use socket:// for "raw")
    add name="serial2http" key="SERIALURL" value="rfc2217://172.22.17.254:22171?ign_set_control&logging=debug&timeout=3"
    # most options can be set in the pyserial's url, BAUDRATE must be explicit 
    add name="serial2http" key="BAUDRATE" value=115200
    # timeout to use if not in pyserial's url 
    add name="serial2http" key="TIMEOUT" value=5
}
```
_To remove, use `/container/envs [find name="serial2http"] remove`_

## Step 2. Setup mounts to modify the source code
If you want to edit the python code later, you can add a mount.  The code gets installed into `/app` within the container, and that directory can be exposed to RouterOS.  In RouterOS, the `dst=` is a directory within the container, and the `src=` is the RouterOS path to use.  
_Below assumes `disk1/` as the RouterOS storage location – adjust command as needed._

```
/container/mounts {
    add name=serial2http src=disk1/serial2http-app dst=/app
}
```
_To remove, use_ `/container/mount [find name="serial2http"] remove` _to revert the above command_

> **Important** RouterOS path do NOT start with a slash "/", so the src= should NOT have a `/` at start. 

## Step 3. Create IP network for the container

```
/interface/veth {
    add name=veth-serial2http address=172.22.17.1/24 gateway=172.22.17.254
}
/ip/address {
    add interface=veth-serial2http address=172.22.17.254/24
}
```
_To remove, use two commands_
 `/interface/veth/remove [find name=veth-serial2http]` and
 `/ip/address/remove [find interface=veth-serial2http]`

## Step 4. Map a physical serial port to an TCP port

This part is simple, but you'll need to adjust `port=` for the particular physical serial port (or USB-based serial) device.  The examples above assume the remove port lives at `172.22.17.254` using TCP port `22171`.
```
/port remote-access add port=serial0 protocol=rfc2217 tcp-port=22171
```

If you use something different here, adjust the `SERIALURL` in `/container/envs` to match the specific devices.

> **Security and Firewalls** You need to adjust the firewall to the scope need to support.  The default firewall will allow only access from the same device using the examples (since the veth is not in any address-list).  But the `tcp-port=` listens on **all** interfaces, so the firewall configuration needs to be property secured. 

> **Side Note** Since the relevent serial-to-IP protocol is defined RFC-2217, the IP use "22.17" and port contains the RFC number.

## Step 5. Creating the RouterOS container itself

There are two ways to do this:
* "pull" the GitHub-built image from this repo using `/container add remote-image= ...` (option 1)
* **OR** use `docker build[x]` on your desktop (option 2) 

### Option 1: To use `https://ghcr.io` to "pull" the image

To download the container by it's tag, you'll need to use the GitHub Container Registry first. 
```
/container/config/set registry-url=https://ghcr.io
```
Once successfully imported to RouterOS, the image is uneffected if the registry is changed after import into `/container`.  

You can revert to the more common Docker Hub after a successful import, by using: `/container/config/set registry-url=https://registry-1.docker.io`

```
/container/add remote-image=ghcr.io/tikoci interface=veth-serial2http env=serial2http mounts=serial2http-app logging=yes root-dir=disk1/serial2http-container

```

> **Side Note** This image is only in the ghcr.io registry.  It is NOT is DockerHub.  While trivial to push to DockerHub in addition to the GitHub Container Registry...one registry seems enough for an unusual use case. 


### Option 2: Or, build locally using `docker build` and copy `.tar` file

In some ways this is simplier, since the resulting `.tar` is just the needed filesystem.  If the package method above does not work, try this method.

You'll need the Docker Desktop installed first.  Using the "Code" dropdown in GitHub, you can download or `git clone` to a folder on your desktop system. Then run standard `docker build` from that folder in a terminal:  
```
docker build --platform linux/arm/v7 -t serial2http .     
docker save serial2http > ../serial2http.tar  
```
The .tar file will be in the parent directory.  You can copy and install on your router.  If we assume the image is in `disk1/serial2http.tar`, the following command will use the file image, instead of the tag as in option 1 above:

```
/container/add file=disk1/serial2http.tar interface=veth-serial2http env=serial2http mounts=serial2http-app logging=yes root-dir=disk1/serial2http-container

```
The image will need to be "extracted", so wait a minute then try to start it.  Once extracted and in a "stopped" state, you can start it:

## Step 7. Start the container

After adding the container, and assoicate config, you can start the container using:
```
/container [find tag~"serial2http"] start
```

> **Tip** To do a UNIX-like `watch` on container status live via CLI, use `/container print interval=1s ...`:
> ```
> /container print interval=1s proplist=tag,status where tag~"serial2http"
> ```

## Step 8. Test the container

This part is trickier here. You'll need a serial device connected that uses a request-response API that ends response with a `\n`.  NMEA, typically used with GPS and marine applications, is one such protocol.  

> **Example** This container was orignally built to use with the [Swarm M138 modem](https://swarm.space/documentation-swarm/) to work with https://swarm.space to allow RouterOS to send/recieve message via satellite to swarm's "hive" cloud service.  Unlike LTE modems (e.g. AT commands), the M138 modem uses NMEA-style commands – so `at-chat` does not work – thus this container.  But likely useful in other context too. 

To use, the general steps are:

1. You have a serial device that needs to work with RouterOS script.  You can use `/ports/print` to show the serial ports found. 
2. In `/ports/remote-access`, you may have to change `port=` to match the serial port where the device is connection.
3. You'll need to know the commands you want to send/recieve.  Taking the Swarm M138 modems, the configuration can be obtained by doing the following:

> **Tip**  It may be possible some serial devices are detected as LTE devices (and/or you want to use with an LTE modem).  If this is case, and you don't have any "real" LTE interface, set the LTE modem detection to use "serial" instead of "auto" or "mbim".  To do this use:
> ```
> /interface/lte/settings/set mode=serial 
> ```

# Security Considerations

Both sides of the proxy use insecured IP traffic, so you'd want to think about how best to use RouterOS firewall to best protect both:
* port used in `/tool/remote-access` used to expose a serial port to TCP
* container's subnet which listens on `HTTP` on port 80 for commands to send

Thus, it recommended that users configure their firewall to limit exposure of any IP and ports used by this container.  


# Help? 

Use the the repo's issue tracking for any questions or problems.  Pull requests, suggestions, or recommendations will be consider as time allows.

# Notices 

> **No liability for the contents of this document or code can be accepted.** Use the concepts, examples and other content at your own risk. There may be errors and inaccuracies, that may of course be damaging to your system. Although this is highly unlikely, you should proceed with caution. The author does not accept any responsibility for any damage incurred.

> **Any trademarks and/or copyrights remain the property of their respective holders**, unless specifically noted otherwise.
> Use of a term in this document should not be regarded as affecting the validity of any trademark or service mark. Naming of particular products or brands should not be seen as endorsements.
> MikroTik is a trademarks of Mikrotikls SIA.
> Python is a registered trademark of the PSF. 
> UNIX is a registered trademark of The Open Group.
> Docker and the Docker logo are trademarks or registered trademarks of Docker, Inc. in the United States and/or other countries. 
> Docker, Inc. and other parties may also have trademark rights in other terms used herein.


