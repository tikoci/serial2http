###
###  Installer for "SERIAL2HTTP" 
###
:put "** starting "

## MAIN SETTINGS FOR CONTAINER INSTALL

:global SERIAL2HTTP
:set SERIAL2HTTP do={
    :global SERIAL2HTTP 
    :local arg1 $1
    :local arg2 $2
    :local action 0
    :if ([:typeof $arg1]="str") do={
        :set action $arg1
    }

    # name of container, used in comment to find - could be multiple so add a "containername1[2,...]" to things 
    :local containernum "" 
    :local containername "serial2http" 
    :local containertag "$(containername)$(containernum)"
    :local containerethname "veth-$(containertag)"

    # RouterOS IP config
    :local containeripbase "172.22.17"
    :local containerprefix "24"
    :local containergw "$(containeripbase).254"
    :local containerip "$(containeripbase).1"

    :local containerregistry "ghcr.io"
    :local ocipushuser "tikoci"


    # "$SERIAL2HTTP build" - removes any existing and install new container
    :if ($action = "build") do={
        ## WARN BEFORE CONTINUE
        :put "continuing will KILL and RE-SPAWN the $containertag container!"
        :put "...starting in 5 seconds - hit ctrl-c now to STOP"
        :delay 5s


        # RouterOS root to use for 
        # path= option
        :local rootdisk
        :if ([:typeof $path]="str") do={
            :set rootdisk $path
        } else={
            :set rootdisk "disk1"
        }
        :local rootpath "$(rootdisk)/$(containertag)"



        ## SERIAL2HTTP-SPECIFIC CONFIG
        :local serialnetport
        :if ([:typeof $containernum]!="num") do={
            :set serialnetport "22171"
        } else={
            :set serialnetport "2217$[:tostr $containernum]" 
        }

        # picks first port with channels, adapt as need to "usb1" or whatnot
        # unless port= is specified when invoked
        :local serialport 
        :if ([:typeof $port]="str") do={
            :set serialport $port 
        } else={
            :local firstserial ([/port print as-value where channels>0]->0->"name")
            :if ([:typeof $firstserial]="str") do={
                :put "using first serial port $firstserial to connect to container"
                :set serialport $firstserial 
            } else={
                :error "no serial port specified in port= and none were found to use a default"
            }
        }
        :put "selected TCP port $serialnetport to connect container to serial port $serialport"

        # enable TCP access to $serialport via
        /port/remote-access {
            # does suport comments
            remove [find port=$serialport ]
            :local serialnet [add port="$serialport"]
            set $serialnet allowed-addresses="0.0.0.0/0"
            set $serialnet log-file="$(rootpath)-remote-port.log" 
            set $serialnet protocol=rfc2217
            set $serialnet tcp-port=[:tonum "$serialnetport"]
            enable $serialnet
        }

        # setup container settings
        /container/envs {
            remove [find name="$containertag"]
            add name="$containertag" key="PORT" value=80 
            add name="$containertag" key="SERIALURL" value="rfc2217://$(containergw):$(serialnetport)?ign_set_control&logging=debug&timeout=5"
            add name="$containertag" key="BAUDRATE" value=115200
            add name="$containertag" key="TIMEOUT" value=5
        }
        /container/mounts {
            # serial2http doesn't use mounts
            remove [find name~"$containertag"]
            add name="$containertag" src="$(rootpath)-app" dst=/app
        }

        ## START GENERIC CONTAINER CONFIG

        /interface/veth {
            remove [find comment~"$containertag"]
            :local veth [add name="$containerethname" address="$(containerip)/$(containerprefix)" gateway=$containergw comment="#$containertag"]
            :put "added VETH - $containerethname address=$(containerip)/$(containerprefix) gateway=$containergw "
        }
        /ip/address {
            remove [find comment~"$containertag"]
            :local ipaddr [add interface="$containerethname" address="$(containergw)/$(containerprefix)" comment="#$containertag"]
            :put "added IP address=$(containergw)/$(containerprefix) interface=$containerethname"
        }
        /interface/list/member {
            remove [find comment~"$containertag"]
            :local iflistmem [add interface="$containerethname" list=LAN comment="#$containertag"]
        }
        /container {
            :local containerexisting [find comment~"$containertag"]
            :foreach containerinstance in=$containerexisting do={
                :do { stop $containerinstance } on-error={}
                :while (!([get $containerinstance status]~"stopped|error")) do={
                    :delay 10s
                    :put "removing old container $containerinstance, waiting for stop"
                }
                remove $containerinstance
                :put "old container $containerinstance stopped and removed"
            }

            :local containerid 
            :if ([:typeof $tarfile]="str") do={
                :put "adding new $containertag container on $containerethname using $(rootdisk)/$(containername).tar"
                :set containerid [add file="$tarfile" interface="$containerethname" env="$containertag" logging=yes root-dir="$(rootpath)-root"]
            } else={
                :local containerver "main"
                :if ([:typeof $branch]="str") do={
                    :set containerver $branch
                } 
                :local lastreg [$SERIAL2HTTP registry github]
                :local containerpulltag "$(containerregistry)/$(ocipushuser)/$(containername):$(containerver)"
                :put "pulling new $containertag container on $containerethname using $containerpulltag"
                :set containerid [add remote-image="$containerpulltag" interface="$containerethname" env="$containertag" logging=yes root-dir="$(rootpath)-root"]
                [$SERIAL2HTTP registry url=$lastreg]
            }
            set $containerid comment="#$containertag"
            set $containerid start-on-boot=yes
            set $containerid mounts="$containertag"
            :local waitstart [:timestamp]
            :while ([get $containerid status]!="running") do={
                :put "$containertag is $[get $containerid status]";
                :if ([get $containerid status] = "error") do={
                    :error "opps! some error importing container"
                }
                :if ([get $containerid status] = "stopped") do={
                    :put "$containertag sending start";
                    :do { start $containerid } on-error={}
                    
                }
                :delay 10s
                :if ( [:timestamp] > ($waitstart+[:totime 90s]) ) do={
                    /log print proplist=
                    :put "opps. took too long..."
                    :put "dumping logs..."
                    /log print proplist=message where topics~"container"
                    :error "opps. timeout while waiting for start.  check logs above for clues and retry build."
                }
            }
            :if ([get $containerid status] = "running") do={
                :put "$containertag started"
            } else={
                :error "$containertag failed to start"
            }
        }
        / {
            :put "** done"
        }
    }

    :if ($action = "registry") do={
        /container/config {
            :local curregurl [get registry-url]
            :if ([:typeof $url]="str") do={
                :put "registry set to provided url: $url"
                set registry-url=$url 
                :return $curregurl 
            }
            :if ([:typeof $arg2]="str") do={ 
                :if ($arg2~"github|ghcr") do={
                    set registry-url="https://ghcr.io"
                    :put "registry updated from $curregurl to GitHub Container Store (ghcs.io)"
                    :return $curregurl
                }
                :if ($arg2~"docker") do={
                    set registry-url="https://registry-1.docker.io"
                    :put "registry updated from $curregurl to Docker Hub"
                    :return $curregurl
                } else={
                    :error "setting invalid or unknown registry - failing"
                }
            } else={
                :put "current container registry is: $curregurl"
                :return $curregurl
            }
        }
    }
    :error "use '$SERIAL2HTTP build port=<port> path=<disk>' to replace/add container."
}
