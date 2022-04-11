# Network-with-DMZ
Network Security Project 
Configuration of a Company Network with DMZ protected by two firewalls automated using a script bash.

## Getting Started

### Progetto folder

First, go in the "Progetto" folder and execute the following script:

```bash
# to build the network configuration and insert the rules automatically in the firewalls tables
./config
```

Enter in one of the two docker containers (cliente1 or host1) in order to test the rules. You can use the commands in the file comandi_utilizzati.

The more efficent way to test the rules is to use the daemon ulogd2, that allows to log the packets that pass through the network.

Ulogd2 syntax rule:

```bash
docker exec --privileged -t firewall1 iptables -A FORWARD -j NFLOG --nflog-prefix="FORWARD Log rule-name: "
```

For further information about the log, check the config.sh file at line 137-144 and the documentation.

You can see the results following the path /var/log/ulog in the tested firewall, opening the syslogemu.log file. 

In case of any problems with the log you can restart the ulog daemon in the firewall:

```bash
service ulogd2 restart
```

The log file can be used to analyze the traffic passing through the network, eventually for future purposes.


Execute the following script to clean the configuration:
```bash
./pulizia.sh
```

### DSP folder

In this folder there are two subfolders:
- Docker-Compose Locale, that works as the previous configuration, but with a docker-compose file (without rules);
- Progetto1.0, the DSP (Docker Security Playground) repo.
