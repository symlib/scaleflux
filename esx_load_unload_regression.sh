#!/bin/bash -x

if [ $newinstall = true ];then

for ((i=1; i < 8; i++)); do
			dating=`ls /share/releases/Daily/ | sort -r | sed -n ${i}p`
			revision=`ls /share/releases/Daily/$dating/$rpmBranch/esx6.5 | sort -r | sed -n 1p`
			dir="/share/releases/Daily/$dating/$rpmBranch/esx6.5/$revision"
			
			if [ -d $dir ]; then
				echo $revision
				break
			fi
done
#please setup ssh access without password to esxi
ssh root@$esxihost "esxcli software vib list|grep sfx"
if [ $? = 0 ]; then
	ssh root@$esxihost "esxcli software vib remove --vibname=sfx-esx-sfx-esxcli-plugin"
	ssh root@$esxihost "esxcli software vib remove --vibname=sfxnvme"
    ssh root@$esxihost "esxcli software vib remove --vibname=sfx-esx-sfx-cli"
	ssh root@$esxihost "reboot"
    sleep 200
    cd $dir
	scp *.vib root@$esxihost:/
	if [ $? = 0 ];then
		ssh root@$esxihost "esxcli software vib install  -f -v /SFX-ESX-sfx-esxcli*.vib"
        ssh root@$esxihost "esxcli software vib install  -f -v /SFX-ESX-sfx-cli*.vib"
		ssh root@$esxihost "esxcli software vib install  -f -v /sfxnvme*.vib"
        ssh root@$esxihost "reboot"
       
    fi
elif [ $? = 1 ];then
	cd $dir
	scp *.vib root@$esxihost:/
	if [ $? = 0 ];then
		ssh root@$esxihost "esxcli software vib install  -f -v /SFX-ESX-sfx-esxcli*.vib"
        ssh root@$esxihost "esxcli software vib install  -f -v /SFX-ESX-sfx-cli*.vib"
		ssh root@$esxihost "esxcli software vib install  -f -v /sfxnvme*.vib"
        ssh root@$esxihost "reboot"
        #sleep 200
	else
		echo "Cannot copy the latest vibs to esxi"
		exit 1
	fi
else
	echo "Cannot connect to esxi host"
    exit
fi

sleep 200
fi

ping $esxihost -c 2
TIMEOUT=200
to=0
while true; do
	ssh root@$esxihost "pwd"
    if [ $? = 0 ];then
    	break
    fi
    sleep 1
    to=$((to+1))
    if [ $to = $TIMEOUT ];then
    	echo "TIME out for connect to esxi"
        rc=`expr ${rc} + 1`
        exit 1
    fi
done
# if the network connection is alive
if [ $? = 0 ];then

			ssh root@$esxihost "esxcli software vib list|grep sfx"
			if [ $? = 0 ]; then
            	echo "install driver successfully."
			else
            	echo "install driver failed"
                rc=`expr ${rc} + 1`
                exit 1
            fi
fi

rc=0
echo "`date`: Load/Unload sfxnvme driver"



ssh root@$esxihost "echo '`date`: load/unload sfxnvme driver $revision' > /scratch/log/vmkernel.log"

ping $vmip -c 2
if [ $? = 0 ];then
        ssh hscaleflux@$vmip "sudo mkfs.xfs /dev/sdb -f"
else
	echo "`date`: vm is not reachable."
	exit 1
fi

for loop in {1..${loops}..1};do
	
        ssh hscaleflux@$vmip "sudo mount /dev/sdb /mnt;sudo bash -c 'echo "this is my test ${loop}" >> /mnt/test'; sudo bash -c 'md5sum /mnt/test > /mnt/md5sum.txt'; sudo sync; sudo sync"
        
        
        if [ $? = 0 ]; then
            echo "`date`: before unload -- Passed"
            echo "`date`: unload sfxnvme driver -- start"
            # assume that there's only one vm in the esxi"
            ssh root@$esxihost "vim-cmd vmsvc/power.off 1"
            
            ssh root@$esxihost "esxcli system coredump partition set -u"
            rc=`expr ${rc} + 1`
            ssh root@$esxihost "esxcli storage core claiming unclaim -t driver -D sfxnvme"
            rc=`expr ${rc} + 1`
            ssh root@$esxihost "vmkload_mod -u sfxnvme"
            if [ $? = 0 ]; then
            	echo "`date`: unload driver -- ${loop} passed"
            else
            	echo "`date`: unload driver -- ${loop} failed"
            	rc=`expr ${rc} + 1`
                break                
            fi
        else
            echo "`date`: before unload -- Failed"
            rc=`expr ${rc} + 1`
        fi
        
        echo "`date`: load sfxdriver ..."
        ssh root@$esxihost "vmkload_mod /usr/lib/vmware/vmkmod/sfxnvme"
        ssh root@$esxihost "kill -SIGHUP $(cat /var/run/vmware/vmkdevmgr.pid)"
        if [ $? = 0 ]; then
            ssh root@$esxihost "vim-cmd vmsvc/power.on 1"
            sleep 20
            ping $vmip -c 2
			if [ $? = 0 ];then
                  ssh hscaleflux@$vmip "sudo mount /dev/sdb /mnt;sudo bash -c 'md5sum /mnt/test > /mnt/md5sum2.txt'"
                  ssh hscaleflux@$vmip "sudo bash -c 'diff /mnt/md5sum2.txt /mnt/md5sum.txt'"
                  if [ $? = 0 ]; then
                      echo "`date`: load driver -- ${loop} passed"
                     
                  else
                      echo "`date`: load driver -- ${loop} failed"
                      rc=`expr ${rc} + 1`
                      break
                  fi				 
            else
                echo "`date`: load driver -- ${loop} failed"
                rc=`expr ${rc} + 1`
                break
            fi
		fi
            
done



scp root@$esxihost:/scratch/log/vmkernel.* $WORKSPACE/


if [ $rc -eq 0 ]; then
    echo "Test: load/unload driver ==> SUCCEEDED"
else
    echo "Test: load/unload driver ==> FAILED"
    exit 1
fi