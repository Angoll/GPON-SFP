# EdgeRouter with GPON SFP module

This is how I replaced my Movistar / O2 HGU router with a GPON ONU SFP module to my EdgeRouter 4.

After using the ISP provided router in BridgeMode for quite a while I decided to go a step further.

> **_Disclamer:_**  All material and information contained here is for general information purposes only. Use it as your own risk.

Most of this information is related to the Movistar / O2 ISP in Spain. As is the one I have.

## Introduction

There is not much information on Internet about how to do it for a specific ISP. I undesrtand it some ISP do not allow it or can ban you.

I found the web site <https://hack-gpon.org> there is a lot of information on the subject and has very detailed guides.

In theory it should be as easy as buying a GPON module, configure the required authentication methods and connect the fiber line. In reality the process is more complex. I focused on separate the process into two problems.

1. Have a `O5` Operation state connection with the ISP OLT.
    That means connecting and authenticate correctly to the fiber line.

2. The second one discover the VLANs that I had to use.

## The SFP GPON Module

There are a lot of diferent GPON modules and with the increase of higher bandwidth offers some are moving to XPON modules. So selecting one and find it on sale is a challenge by itself.

For me, I decided to go with GPON with SFP. The fact that the edge router only have one SFP 1GB port and my internet badwith is 600/600 Mbps. To take advandage of a XPON module speeds you need a SFP+ port and connections of > 940 Mbps ( > 1Gbps if no headers are taking into account).

I bought the `FS GPON-ONU-34-20BI` to give a try. Later I discovered that the chipset is a **Lantiq**. Chipsed that no longer exists and maintaned and most manufactures are moving to Realtek chipsets [[1]](#1).

## Movistar / O2

From the ISP provider we need to know the authentication configuration and the VLAN information.

This ISP ony uses a Password as authentication method, this password is also known as `PLOAM`/`IdONT`. The password can be found in the router website [[2]](#2). Usually starts with an F and is arround 20 characters.

Thne we need to know the VLAN configuration, for this ISP the configuration is the following a triple VLAN for their servies:

- **VLAN 6** for internet access
- **VLAN 3** for VoIP telephone
- **VLAN 2** for IPTV for the TV services

I don't have the TV it is not covered in here. My main focus is the internet access. I did not explore the VoIP configuration yet, but there are quite others tutorials on how to configure it.

With all the information of the `bridge Mode` I was already aware that I needa PPPoE to get the public IP address.

## The architecture

What we try to accomplish is the following:

```bash
+---- EdgeRouter 4 ------------+-+--- GPON SFP ---------------+----+-- ISP -----------+
| PPPoE --> Vlan 3.6 --> Eth 3 ->- vlan over vlan QinQ -> GEM =====> OLT ISP Internet |
```

## EdgeRouter configuration

I'm not going to go into much details on how to configure it. But the gist is the following:

- _eth3_ is the SFP Port
- Create a VLAN _eth3.691_ <- The Vlan ID depends on what the ISP is using.
- Create a PPPoE with parent port the VLAN created:

|||
|---:|---|
|Account Name:| adslppp@telefonicanetpa|
|Password:|adslppp|
|MTU:|14292|

- Create a NAT rule to masquerade for PPPoE.

### Extra access GPON SSH

My GPON SFTP module only has SSH enabled to be able to configure it. The default values are

|||
|--|--|
|IP address | 192.168.1.10 |
| SSH | user `ONTUSER` password `7sp!lwUBz1` |
|Serial | on SFP |
|Serial baud | 115200 |
|Serial encoding | 8-N-1|

To be able to route trafic to it, I created a new NAT rule with Destination the new configured IP TCP port 22 using masquerade and outbound interface eth3.

And to be able to access it via SSH I had to enable old KeyAlgorithms:

```bash
ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 ONTUSER@192.168.1.10
```

As the default IP address conflicts with my network I changed the IP to another range:

```bash
fw_printenv ipaddr  # Check configured IP
fw_setenv ipaddr 192.168.250.10 # New IP
```

## GPON SFP configuration

First of all we need to be able to authentificate to the ISP. I followed the documentation [[3]](#3) but I hit the first issue. This ISP the PLOAM password is in hex fromat and it has unprintable characters when converted to ascii.

### Hex PLOAM format

A PLOAM password is allways 10 ascii characters.
The GPON SFP configuriguartion cli tools only accept 10 ascii characters that must be printable.

I configured the `nPassword` as following

```bash
fw_setenv nPassword "\x12\x34\x56\x78\x9a\xab\xbc\x00\x00\x00" # where `12 34 56 78 9a xb xbc ...` will the IdONT values.
```

After I updated the `/etc/init.d/onu.sh` script to add the follwing line after the _if_ of getting the nPassword:

```bash
...
nPassword=$(echo -ne "${nPassword}" | hexdump -v -e '/1 "0x%02X "' | xargs)
...
```

I connected the fiber line and I got a `O5` state, I also did a tcpdump on the EdgeRouter SFP interface and I could start to see packages from the internet.

## The vlan issues

As I started from a Bridge Mode I had configured the PPPoE over the VLAN 3.6 (VID 6) and the edgerouter logs were only showing messaged like:

```
Timeout waiting for PADO packets
```

I started inspecting all traffic on the interface eth3 using the command `tcpdump -i eth3 -e  vlan -n -Q inout`. I discovered that I was recieving traffic from VLAN 3 and the PADO responses tagged with VLAN 691.

I tried to configure replace the VLAN 6 with VLAN 691 but I was not recieving any PADO responses back.

After a lot of digging I discovered the existence of managed entity ID 171 **Extended VLAN tagging operation configuration data**. This table contains the configuration parameters for enhanced VLAN operations, including adding, removing and changing multiple tags. This table translates the input packages to internal packages this translation consists on priority and vlan ID. I discovered that VLAN 6 was modified to VLAN 691.

**Extended VLAN tagging operation configuration data** is created and managed by the ISP OTL when connected. The table only contains the information for the upstream packages and for the downstream packages is performing the reverse operation.

But after a lot of strugling the reverse operation was not working correctly, still don't know why.

After some checks on the TPID and QoS values, I decided to remove the translation table and send traffic to the internal VLAN directly in my case VLAN 691.
I configured a `/etc/init.d/remove_vlan_ext.sh` script to every 30 seconds check if the table exists and remove it.

**And it works!**:tada:

## Changing the firmware for Huawei MA5671A

After some speed test the downspeed was correct but the uploads was flaky and not getting the full performance comparted to the ISP in bridge mode.

When facing the PLOAM hex to ascii issues I decided to change the firmware in the secondary boot partition to the Huawey MA5671A following the instructions [[4]](#4).

This firmware accepted hex password and I only configured the script to remove the Extended VLAN tagging table automatically.

I run again the speed tests and the performance was much better, maching the ISP bridge mode. Upspeed and downspeed directly to max value.

## Usefull commands

```bash
## Get the operational state
onu ploam_state_get

# Get optical laser status
otop -g s

# Get information on the ONU connection and OLT configuration
gtop

# Configure and manage the onu entities
onu help

# Configure  and manage entities
omci_pipe.sh help
omci_pipe.sh mib_dump
omci_pipe.sh mib_dump_all


```

## References

There is not much information out there so I have to thank a lot to hack-gpon to the awsesome documentation.

<a id="1" href="https://hack-gpon.org/ont/">[1] <https://hack-gpon.org/ont/></a>

<a id="2" href="<https://bandaancha.eu/foros/sacar-clave-gpon-idont-ploam-password-1742313">[2] <https://bandaancha.eu/foros/sacar-clave-gpon-idont-ploam-password-1742313></a>

<a id="3" href="https://hack-gpon.org/ont-fs-com-gpon-onu-stick-with-mac/">[3] <https://hack-gpon.org/ont-fs-com-gpon-onu-stick-with-mac/></a>

<a id="4" href="https://hack-gpon.org/ont-huawei-ma5671a-fs-mod/">[4] <https://hack-gpon.org/ont-huawei-ma5671a-fs-mod/></a>

<a href="https://github.com/Anime4000/RTL960x">https://github.com/Anime4000/RTL960x</a>
