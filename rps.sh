# Get Empty slot
lsslot -c pci | grep "Empty" | awk '{print $1":"$NF}' > Slot_HWPS.out

# FCS
mFCS=`lsslot -c pci -F ':' | grep fcs | awk -F ':' '{print $3}' | sed 's/pci[0-9][0-9]* //g'`

for mFCSX in `echo $mFCS`
do
   mDES=`lsdev -Cc adapter | awk -v aVAR="$mFCSX" '$1 == aVAR {print $4, $5, $6, $7, $8}'`
   mSLOT=`lscfg -vl $mFCSX | grep $mFCSX | awk '{print $2}'`
   mWWN=`lscfg -vl $mFCSX | awk -F"." '/Network Address/ {print $NF}'`
   echo "$mSLOT:$mDES:$mWWN"
done >> Slot_HWPS.out

# Network
mENT=`lsdev -Cc adapter |grep -i available|grep "ent" | grep -v "Logical" | awk '{print $1}'`
for mENTX in `echo $mENT`
do
netadd=`lscfg -vl $mENTX|grep -i network|awk '{print $2}'`
vpd=`lscfg -vl $mENTX | grep $mENTX | awk '{print $2":"$3,$4,$5,$6,$7}'`
 echo $vpd":"$netadd>> Slot_HWPS.out
done

# Not sorting the Disk output -- change made - 13 oct 2020

sort -t':' -k1,1 -k3,3 -o Slot_HWPS.out Slot_HWPS.out



#SAS - without breaking raid - getting physical disk info
for SAS in $(lsdev -t  sas -F  name)
do
lscfg -l $SAS | read mySAS SASloc SASdesc
print "${SASloc}:${SASdesc}"
 for pdisk in  $(lsdev -p ${SAS} -F name | grep pdisk)
 do
   lscfg -vl ${pdisk} | read myDisk DISKloc DISKDesc
   print "${DISKloc}:${pdisk}:${DISKDesc}"
 done
done >> Slot_HWPS.out
