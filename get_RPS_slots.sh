#!/bin/ksh
SAS_Ctrl_map=/tmp/${0##*/}.SASctrl

function rm_pdisks
{
# list the disks not configured under a VG (no-pvid)
disk_nopvid="$(lspv|awk '$3=="None" {print $1}')"

# filter raid disks 
raid_disks=""
for disk in `echo ${disk_nopvid}`
do
	is_raid=""
	is_raid=$(lsdev -l ${disk}|grep -i raid)
	if [ ! -z "${is_raid}" ]
	then
		raid_disks=${raid_disks}" "${disk}
	fi
done

# if they are SAS disks then delete the raid
for disk in `echo ${raid_disks}`
do 
	parent=$(lsdev -l ${disk} -F parent)
	issas=$(echo ${parent}|grep -i sas)
	if [ ! -z "${issas}" ]
	then
		sasadapter=$(lsdev -l ${parent} -F parent)
		#Delete the RAID
		sissasraidmgr -D -l ${sasadapter} -d ${disk}
	fi
done

# above would have deleted any SAS Raid Arrays and would have left the pdisks as
# "Array candidates" pdisks correcponding to the hdisks which are part of VGs will
# still be Array members as those hdisks are not touched

# get the list of pdisks
pdisks=$(lsdev|grep -i pdisk|awk '{print $1}')

# filter the candidate pdisk list 
candidate_pdisks=""
for disk in `echo ${pdisks}`
do
	is_candidate=""
	is_candidate=$(sissasraidmgr -L -l ${disk}|grep -i candidate)

	if [ ! -z ${is_candidate} ]
	then
		candidate_pdisks=${candidate_pdisks}" "${disk}
	fi
	is_candidate=""
done

# Now format the candidate disks in background to jbod
for pdisk in `echo ${candidate_pdisks}`
do
	#check if this disk is already formatting
	is_formatting=""
	is_formatting=$(ps -ef|grep -i sissasraidmgr|grep -i ${pdisk})

	if [ -z "${is_formatting}" ]
	then
		#Format this pdisk to JBOD in background the converted device will be renamed as hdisk and pdisk is gone.
		sissasraidmgr -U -z ${pdisk} &
	fi
	is_formatting=""
done
wait    # wait for all the background jobs to complete
}       # END function rm_pdisks

# First, convert all SAS RAID arrays to JBOD
rm_pdisks

# Get Empty slots
lsslot -c pci | grep Empty | awk '{print $1"::"$NF}' > RPS_slots.out

# Get FCS adapters
for myFCSX in $(lsslot -c pci -F ':' | grep fcs | awk -F ':' '{print $3}' | sed -e 's/pci[0-9]*//g' -e 's/ent[0-9]*//g')
do
	myDESC=$(lscfg -l $myFCSX | awk '{print $3,$4,$5,$6,$7,$8,$9,$10,$11}')
	mySLOT=$(lscfg -l $myFCSX | awk '{print $2}')
	myWWN=$(lscfg -vl $myFCSX | awk -F'.' '/Network Address/ {print $NF}')
	echo "$mySLOT:$myDESC:WWPN=${myWWN}" >> RPS_slots.out
done

# Get Network adapters
for myENTX in $(lsdev -Cc adapter |grep ent | grep -v Logical | awk '{print $1}') 
do
	myMAC=$(lscfg -vl $myENTX | awk -F'.' '/Network Address/ {print $NF}')
	myDesc="$(lscfg -l $myENTX | awk '{print $3}')"
	case ${myDesc} in
	[Nn]/[Aa]*)
		Loc="$(lscfg -l $myENTX | awk '{print $2}')"
		Desc="$(lscfg -vl $myENTX | awk '/PCIe/ {print $1,$2,$3,$4,$5,$6,$7,$8,$9}')"
		print "${Loc}:${Desc}:MAC=${myMAC}" >> RPS_slots.out
		;;
	*)	lscfg -l $myENTX | awk -v MAC=$myMAC '{print $2":"$3,$4,$5,$6,$7,$8,$9,$10,$11":MAC="MAC}' >> RPS_slots.out
		;;
	esac
done

# Get SAS Disks and SAS Controllers
# Create a SAS disk to SAS controller map
for sissas in $(lsdev -C -F name | grep sissas)
do
	sas=${sissas#sis}
	sissasLOC=$(lscfg -l ${sissas} | awk '{print $2}')
	lsdev -p ${sas} | grep -v sfwcomm | awk '{print $1}' | sed "s/^.*$/${sissas} & ${sissasLOC}/"
done > ${SAS_Ctrl_map}

# Get SAS Controllers
for myCtrlr in $(awk '{print $1}' ${SAS_Ctrl_map} | sort -u)
do
	lscfg -l ${myCtrlr} | awk '{print $2":"$3,$4,$5,$6,$7,$8,$9,$10,$11":"}'
done >> RPS_slots.out

# Get SAS Disks
for endDev in $(awk '{print $2}' ${SAS_Ctrl_map})
do
	print "$(lscfg -l ${endDev} | awk '{printf("%s:%s %s %s %s %s %s\n",$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)}'):Controller=$(awk -v myDev=${endDev} '$2==myDev {print $3}' ${SAS_Ctrl_map})"
done >> RPS_slots.out
grep -v 'PCI Express Bus  ' RPS_slots.out | sort -u -k1 -o RPS_slots.out
print "Output of ${0##*/} sent to RPS_slots.out"

