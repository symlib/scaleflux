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

 	

rc=0
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


echo "`date`: Random injecting errors into NAND for programming -- Start"
echo "sfx_inject to esx host"
echo "backup vmkernel.log......"
ssh root@$esxihost "cp /scratch/log/vmkernel.log /scratch/log/vmkernel.bk_programming.log"
ssh root@$esxihost "echo '' > /scratch/log/vmkernel.log"
ssh root@$esxihost "echo '`date`: beginning Random injecting errors into NAND for programming on $revision' > /scratch/log/vmkernel.log"

ssh root@$esxihost "/opt/scaleflux/bin/sfx-cli --op inject -A vmhba1 0 0 0xf5 5 1"
ssh root@$esxihost "tail -n 10 /scratch/log/vmkernel.log"|grep "EHANDLE add injection"

if [ $? = 0 ];then
	ssh hscaleflux@$vmip "cd sfx_qual_suite/;sudo ./sfx_run_benchmark --size 2980G --filename /dev/sdb --no-clean --system-name CRN-INJECT --bs 128K --queue-depth 256 --timebased --runtime 2100 --type seq_write_qd &" &
    for se in {0..2100..100};do
	{
		
        sleep 100
        echo "check EHANDLE: inject err"
		ssh root@$esxihost "grep 'inject err' /scratch/log/vmkernel.log"
		
		if [ $? =  0 ];then
        		echo "error inject logs are there in messages."
                
		else			
            rc=`expr ${rc} + 1`
            echo "`date`: no inject err log during passed 100 seconds"
            #exit 1                       
		fi		
		
	};
	done
    echo "wait for 100 seconds, then poweroff esx host"
    sleep 100
    echo "wait for powering off esx host"
    ssh root@$esxihost "poweroff"
    TIMEOUT=200
    to=0
    while true; do
    	sleep 1
        ssh root@$esxihost "pwd"
        if [ $? = 255 ];then
        	sleep 20
            echo "wol the esxi host"
            wol 2c:56:dc:99:cb:15
            break
        fi
        
        to=$((to+1))
        echo "what is $to"
        if [ $to = $TIMEOUT ];then
            echo "TIME out for wol the esxi host, it might be powered off."
            rc=`expr ${rc} + 1`
            exit 1
        fi
        
    done
    
    TIMEOUT2=200
	to2=0
	while true; do
      ssh root@$esxihost "pwd"
      
      if [ $? = 0 ];then
      	  sleep 80
          echo "wait for VM to start"
          break
      fi
      sleep 1
      to2=$((to2+1))
      if [ $to2 = $TIMEOUT2 ];then
          echo "TIME out for connect to esxi"
          rc=`expr ${rc} + 1`
          exit 1
      fi
	done
    
    ssh hscaleflux@$vmip "lsblk --output=NAME|grep sdb"
    
    if [ $? = 0 ]; then
    	echo "`date`: Random injecting errors into NAND for programming -- Passed"
    else
    	echo "`date`: Random injecting errors into NAND for programming -- Failed"
    	rc=`expr ${rc} + 1`
    fi
 
fi             



echo "`date`: Random injecting errors into NAND for erasing -- Start"
echo "sfx_inject to esx host"
echo "backup vmkernel.log......"
ssh root@$esxihost "cp /scratch/log/vmkernel.log /scratch/log/vmkernel.bk_erasing.log"
ssh root@$esxihost "echo '' > /scratch/log/vmkernel.log"
ssh root@$esxihost "echo '`date`: beginning Random injecting errors into NAND for erasing on $revision' > /scratch/log/vmkernel.log"

ssh root@$esxihost "/opt/scaleflux/bin/sfx-cli --op inject -A vmhba1 0 0 0xf0 5 1"
ssh root@$esxihost "tail -n 10 /scratch/log/vmkernel.log"|grep "EHANDLE add injection"
if [ $? = 0 ];then
	ssh hscaleflux@$vmip "cd sfx_qual_suite/;sudo ./sfx_run_benchmark --size 2980G --filename /dev/sdb --no-clean --system-name CRN-INJECT --bs 128K --queue-depth 256 --timebased --runtime 2100 --type seq_write_qd &" &
    for se in {0..2100..100};do
	{
		
        sleep 100
        echo "check EHANDLE:inject err"
		ssh root@$esxihost "grep 'inject err' /scratch/log/vmkernel.log"
		
		if [ $? =  0 ];then
        		echo "error inject logs are there in messages."
                
		else			
            rc=`expr ${rc} + 1`
            echo "`data`: no inject err log during passed 100 seconds"
            #exit 1                       
		fi		
		
	};
	done
    echo "wait for 100 seconds, then poweroff esx host"
    sleep 100
    echo "wait for powering off esx host"
    ssh root@$esxihost "poweroff"
    TIMEOUT=200
    to=0
    while true; do
    	sleep 1
        ssh root@$esxihost "pwd"
        if [ $? = 255 ];then
        	sleep 20
            echo "wol the esxi host"
            wol 2c:56:dc:99:cb:15
            break
        fi
        
        to=$((to+1))
        echo "what is $to"
        if [ $to = $TIMEOUT ];then
            echo "TIME out for wol the esxi host, it might be powered off."
            rc=`expr ${rc} + 1`
            exit 1
        fi
        
    done
    
    TIMEOUT2=200
	to2=0
	while true; do
      ssh root@$esxihost "pwd"
      if [ $? = 0 ];then
      	  sleep 80
          echo "wait for VM to start"
          break
      fi
      sleep 1
      to2=$((to2+1))
      if [ $to2 = $TIMEOUT2 ];then
          echo "TIME out for connect to esxi"
          rc=`expr ${rc} + 1`
          exit 1
      fi
	done
    ssh hscaleflux@$vmip "lsblk --output=NAME|grep sdb"
    if [ $? = 0 ]; then
    	echo "`date`: Random injecting errors into NAND for erasing -- Passed"
    else
    	echo "`date`: Random injecting errors into NAND for erasing -- Failed"
    	rc=`expr ${rc} + 1`
    fi
 
fi   

echo "`date`: Precondondition for error injection -- Start"
echo "sfx_inject to esx host"
echo "backup vmkernel.log......"
ssh root@$esxihost "cp /scratch/log/vmkernel.log /scratch/log/vmkernel.bk_Precondondition.log"
ssh root@$esxihost "echo '' > /scratch/log/vmkernel.log"
ssh root@$esxihost "echo '`date`: beginning Precondondition for error injection on $revision' > /scratch/log/vmkernel.log"


if [ $? = 0 ];then
	ssh hscaleflux@$vmip "cd sfx_qual_suite/;sudo ./sfx_run_benchmark --type seq_write_qd --size 2980G --filename /dev/sdb --pstats --verify --system-name CRN-TEST --bs 128k --queue-depth 32" 
fi 


echo "`date`: Random injecting errors into NAND for reading -- Start"
echo "sfx_inject to esx host"
echo "backup vmkernel.log......"
ssh root@$esxihost "cp /scratch/log/vmkernel.log /scratch/log/vmkernel.bk_random_reading.log"
ssh root@$esxihost "echo '' > /scratch/log/vmkernel.log"
ssh root@$esxihost "echo '`date`: beginning Random injecting errors into NAND for reading on $revision' > /scratch/log/vmkernel.log"
ssh root@$esxihost "/opt/scaleflux/bin/sfx-cli --op inject -A vmhba1 0 0 2 5 1"
ssh root@$esxihost "tail -n 10 /scratch/log/vmkernel.log"|grep "ERRHDL add injection"


if [ $? = 0 ];then
	ssh hscaleflux@$vmip "cd sfx_qual_suite/;sudo ./sfx_run_benchmark --size 2980G --filename /dev/sdb --no-clean --system-name CRN-INJECT --bs 128K --queue-depth 256 --timebased --runtime 2100 --type seq_read_qd &" &
    for se in {0..2100..100};do
	{
		
        sleep 100
        echo "check EHANDLE: inject err"
		ssh root@$esxihost "grep 'inject err' /scratch/log/vmkernel.log"
		
		if [ $? =  0 ];then
        		echo "error inject logs are there in messages."
                
		else			
            rc=`expr ${rc} + 1`
            echo "`date`: no inject err log during passed 100 seconds"
            #exit 1                       
		fi		
		
	};
	done
    echo "wait for 100 seconds, then poweroff esx host"
    sleep 100
    echo "wait for powering off esx host"
    ssh root@$esxihost "poweroff"
    TIMEOUT=200
    to=0
    while true; do
    	sleep 1
        ssh root@$esxihost "pwd"
        if [ $? = 255 ];then
        	sleep 20
            echo "wol the esxi host"
            wol 2c:56:dc:99:cb:15
            break
        fi
        
        to=$((to+1))
        echo "what is $to"
        if [ $to = $TIMEOUT ];then
            echo "TIME out for wol the esxi host, it might be powered off."
            rc=`expr ${rc} + 1`
            exit 1
        fi
        
    done
    
    TIMEOUT2=200
	to2=0
	while true; do
      ssh root@$esxihost "pwd"
      if [ $? = 0 ];then
			sleep 80
          echo "wait for VM to start"
          break
      fi
      sleep 1
      to2=$((to2+1))
      if [ $to2 = $TIMEOUT2 ];then
          echo "TIME out for connect to esxi"
          rc=`expr ${rc} + 1`
          exit 1
      fi
	done
    ssh hscaleflux@$vmip "lsblk --output=NAME|grep sdb"
    if [ $? = 0 ]; then
    	echo "`date`: Random injecting errors into NAND for reading -- Passed"
    else
    	echo "`date`: Random injecting errors into NAND for reading -- Failed"
    	rc=`expr ${rc} + 1`
    fi
 
fi 

echo "`date`: Injecting errors into NAND for reading -- Start"
echo "sfx_inject to esx host"
echo "backup vmkernel.log......"
ssh root@$esxihost "cp /scratch/log/vmkernel.log /scratch/log/vmkernel.bk_random_reading.log"
ssh root@$esxihost "echo '' > /scratch/log/vmkernel.log"
ssh root@$esxihost "echo '`date`: beginning Random injecting errors into NAND for reading on $revision' > /scratch/log/vmkernel.log"

ssh root@$esxihost "/opt/scaleflux/bin/sfx-cli --op inject -A vmhba1 0x13ffc01f 0xff003ff0 2 5 0"
ssh root@$esxihost "/opt/scaleflux/bin/sfx-cli --op inject -A vmhba1 0x15ffc02f 0xff003ff0 2 5 0"
ssh root@$esxihost "/opt/scaleflux/bin/sfx-cli --op inject -A vmhba1 0x19ffc04f 0xff003ff0 2 5 0"

ssh root@$esxihost "tail -n 10 /scratch/log/vmkernel.log"|grep "EHANDLE"

if [ $? = 0 ];then
	ssh hscaleflux@$vmip "cd sfx_qual_suite/;sudo ./sfx_run_benchmark --size 2980G --filename /dev/sdb --no-clean --system-name CRN-INJECT --bs 128K --queue-depth 256 --timebased --runtime 2100 --type seq_read_qd &" &
    for se in {0..2100..100};do
	{
		nolog=true
        sleep 100
        echo "check EHANDLE"
        for ck in {0..10..1};do
        {
        	sleep 10           
			ssh root@$esxihost "grep 'EHANDLE' /scratch/log/vmkernel.log"
            
			if [ $? =  0 ];then
               nolog=false 
               break;
            else
            	echo "`date`: no read err log, retry $ck"
            fi
         };
         done       
            
		
		if [ $nolog = false ];then
        		echo "error inject logs are there in messages."
                break
		else			
            rc=`expr ${rc} + 1`
            echo "`date`: no read err log during passed 100 seconds"
            #exit 1                       
		fi		
		
	};
	done
    echo "wait for 100 seconds, then poweroff esx host"
    sleep 100
    echo "wait for powering off esx host"
    ssh root@$esxihost "poweroff"
    TIMEOUT=200
    to=0
    while true; do
    	sleep 1
        ssh root@$esxihost "pwd"
        if [ $? = 255 ];then
        	sleep 20
            echo "wol the esxi host"
            wol 2c:56:dc:99:cb:15
            break
        fi
        
        to=$((to+1))
        echo "what is $to"
        if [ $to = $TIMEOUT ];then
            echo "TIME out for wol the esxi host, it might be powered off."
            rc=`expr ${rc} + 1`
            exit 1
        fi
        
    done
    
    TIMEOUT2=200
	to2=0
	while true; do
      ssh root@$esxihost "pwd"
      if [ $? = 0 ];then
      sleep 80
          echo "wait for VM to start"
          break
      fi
      sleep 1
      to2=$((to2+1))
      if [ $to2 = $TIMEOUT2 ];then
          echo "TIME out for connect to esxi"
          rc=`expr ${rc} + 1`
          exit 1
      fi
	done
    ssh hscaleflux@$vmip "lsblk --output=NAME|grep sdb"
    if [ $? = 0 ]; then
    	
    	echo "`date`: Injecting errors into NAND for reading -- Passed"
    else
    	echo "`date`: Random injecting errors into NAND for erasing -- Failed"
    	rc=`expr ${rc} + 1`
    fi
 
fi 



scp root@$esxihost:/scratch/log/vmkernel.* $WORKSPACE/

if [ $rc -eq 0 ]; then
    echo "Test: error injection ==> SUCCEEDED"
else
    echo "Test: error injection ==> FAILED"
    exit 1
fi