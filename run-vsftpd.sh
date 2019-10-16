#!/bin/bash

# If no env var for FTP_USER has been specified, use 'admin':
if [ "$FTP_USER" = "**String**" ]; then
    export FTP_USER='admin'
fi

# If no env var has been specified, generate a random password for FTP_USER:
if [ "$FTP_PASS" = "**Random**" ]; then
    export FTP_PASS=`cat /dev/urandom | tr -dc A-Z-a-z-0-9 | head -c${1:-16}`
fi

# Do not log to STDOUT by default:
if [ "$LOG_STDOUT" = "**Boolean**" ]; then
    export LOG_STDOUT=''
else
    export LOG_STDOUT='Yes.'
fi

# Create home dir and update vsftpd user db:
mkdir -p "/home/vsftpd/${FTP_USER}"
chown -R ftp:ftp /home/vsftpd/

echo -e "${FTP_USER}\n${FTP_PASS}" > /etc/vsftpd/virtual_users.txt
/usr/bin/db_load -T -t hash -f /etc/vsftpd/virtual_users.txt /etc/vsftpd/virtual_users.db

# Set passive mode parameters:
if [ "$PASV_ADDRESS" = "**IPv4**" ]; then
    export PASV_ADDRESS=$(/sbin/ip route|awk '/default/ { print $3 }')
fi

echo "pasv_address=${PASV_ADDRESS}" >> /etc/vsftpd/vsftpd.conf
echo "pasv_max_port=${PASV_MAX_PORT}" >> /etc/vsftpd/vsftpd.conf
echo "pasv_min_port=${PASV_MIN_PORT}" >> /etc/vsftpd/vsftpd.conf
echo "pasv_addr_resolve=${PASV_ADDR_RESOLVE}" >> /etc/vsftpd/vsftpd.conf
echo "pasv_enable=${PASV_ENABLE}" >> /etc/vsftpd/vsftpd.conf
echo "file_open_mode=${FILE_OPEN_MODE}" >> /etc/vsftpd/vsftpd.conf
echo "local_umask=${LOCAL_UMASK}" >> /etc/vsftpd/vsftpd.conf
echo "xferlog_std_format=${XFERLOG_STD_FORMAT}" >> /etc/vsftpd/vsftpd.conf

# Add ssl options
if [ "$SSL_ENABLE" = "YES" ]; then
	echo "ssl_enable=YES" >> /etc/vsftpd/vsftpd.conf
	echo "allow_anon_ssl=NO" >> /etc/vsftpd/vsftpd.conf
	echo "force_local_data_ssl=YES" >> /etc/vsftpd/vsftpd.conf
	echo "force_local_logins_ssl=YES" >> /etc/vsftpd/vsftpd.conf
	echo "ssl_tlsv1=YES" >> /etc/vsftpd/vsftpd.conf
	echo "ssl_sslv2=NO" >> /etc/vsftpd/vsftpd.conf
	echo "ssl_sslv3=NO" >> /etc/vsftpd/vsftpd.conf
	echo "require_ssl_reuse=YES" >> /etc/vsftpd/vsftpd.conf
	echo "ssl_ciphers=HIGH" >> /etc/vsftpd/vsftpd.conf
	echo "rsa_cert_file=/etc/vsftpd/cert/$TLS_CERT" >> /etc/vsftpd/vsftpd.conf
	echo "rsa_private_key_file=/etc/vsftpd/cert/$TLS_KEY" >> /etc/vsftpd/vsftpd.conf
        if [ "$REQUIRE_CERT" = "YES" ]; then
            echo "require_cert=YES" >> /etc/vsftpd/vsftpd.conf
            echo "validate_cert=YES" >> /etc/vsftpd/vsftpd.conf
            echo "ca_certs_file=/etc/vsftpd/cert/$CA_CERTS_FILE" >> /etc/vsftpd/vsftpd.conf
        fi
fi

# Get log file path
export LOG_FILE=`grep xferlog_file /etc/vsftpd/vsftpd.conf|cut -d= -f2`

# stdout server info:
cat << EOB
	*************************************************
	*                                               *
	*    Docker image: akue/vsftd                   *
	*    https://github.com/artjomsk/docker-vsftpd  *
	*                                               *
	*************************************************

	SERVER SETTINGS
	---------------
	· FTP User: $FTP_USER
	· FTP Password: $FTP_PASS
	· Log file: $LOG_FILE
EOB
if [ $LOG_STDOUT ]; then
    /usr/bin/ln -sf /dev/stdout $LOG_FILE
    echo "    · Redirect vsftpd log to STDOUT: Yes."
else
    echo "    · Redirect vsftpd log to STDOUT: No."
fi

# Run vsftpd in background
&>/dev/null /usr/sbin/vsftpd /etc/vsftpd/vsftpd.conf &
vsftpd_pid=$!

# Wait for port 21 to open
while :; do
    &>/dev/null nc -zv localhost 21
    if [ $? -eq 0 ]; then
        echo -e "\n    vsftpd listening on port 21"
        break
    fi
    sleep 1
done

# Re-attach to vsftpd
wait $vsftpd_pid

