#!/bin/bash
# AMI           ami-86e2e4fd
#
#
# VPC
# vpc-aba20dce 
#              (1b) subnet-6459504c (172.16.1.0/24)
#              (1c) subnet-4765a930 (172.16.2.0/24)
#              (1d) subnet-b3ac45ea (172.16.3.0/24)
#               sg  sg-879f0af7

#test="$(cat user.data | base64 -w 0)"


usage ()
{
  echo "Error: $1"
  exit 0
}

function json_set_value() {
  jq "to_entries | 
           map(if .key == \"$1\" 
            then . + {\"value\":\"$2\"} 
            else . 
         end) | from_entries"
}

get_subnet()
{
  subnet_id=$(aws ec2  describe-subnets  --filters "Name=vpc-id,Values=$vpc_id"  "Name=availability-zone,Values=$az_id" \
                                         --output text --query  'Subnets[*].[SubnetId]')
}

#Get instance of spot req
ec2_cmd_sget ()
{
   instance_id=$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids "$spot_id" --output text --query 'SpotInstanceRequests[*].InstanceId')
   echo $instance_id
   aws ec2 describe-spot-instance-requests --spot-instance-request-ids "$spot_id"
}

#Spot req list
ec2_cmd_slist()
{
   aws ec2  describe-spot-instance-requests --output text --query 'SpotInstanceRequests[*].[Status.Code,InstanceId,LaunchSpecification.InstanceType,LaunchSpecification.KeyName,SpotInstanceRequestId,LaunchedAvailabilityZone]'
}

ec2_cmd_sgetip()
{
   instance_id=$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids "$spot_id" --output text --query 'SpotInstanceRequests[*].InstanceId')
   ips=($(aws ec2 describe-instances --instance-ids $instance_id --output text --query 'Reservations[*].Instances[*].[PublicIpAddress,PrivateIpAddress]'))
   echo "Instance: $instance_id PrivateIP: ${ips[1]} PublicIP: ${ips[0]}"
}


ec2_cmd_igetip()
{
   ips=($(aws ec2 describe-instances --instance-ids $instance_id --output text --query 'Reservations[*].Instances[*].[PublicIpAddress,PrivateIpAddress]'))
   echo "Instance: $instance_id PrivateIP: ${ips[1]} PublicIP: ${ips[0]}"
   instance_id_priv_ip=${ips[1]}
   instance_id_publ_ip=${ips[0]}   
   #aws ec2 describe-instances --instance-ids $PARAM
}

#Instance del
ec2_cmd_idel()
{
  aws ec2 terminate-instances --instance-ids $instance_id
}

#Instances list
ec2_cmd_ilists()
{
  aws ec2  describe-instances --filters "Name=key-name,Values=aws_percona_perf" --output text \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress,KeyName,InstanceType,Placement.AvailabilityZone,
  BlockDeviceMappings[*].DeviceName,BlockDeviceMappings[*].Ebs.Status,BlockDeviceMappings[*].Ebs.VolumeId,SpotInstanceRequestId,Tags[*]]'
} 

#Cluster list
ec2_cmd_clist()
{
  aws ec2  describe-instances --filters Name=key-name,Values=aws_percona_perf Name=tag:cluster_name,Values=$cluster_name --output text \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress,KeyName,InstanceType,Placement.AvailabilityZone,
  BlockDeviceMappings[*].DeviceName,BlockDeviceMappings[*].Ebs.Status,BlockDeviceMappings[*].Ebs.VolumeId,SpotInstanceRequestId,Tags[*].Value]' | tr "\n" "\t" | sed -e 's/i-/\ni-/g'
  echo
} 

#Clusters list
ec2_cmd_clists()
{
  aws ec2  describe-instances --filters "Name=key-name,Values=aws_percona_perf" --output text \
  --query "Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,InstanceType,Placement.AvailabilityZone,Tags[?Key=='Name'].Value,Tags[?Key=='cluster_name'].Value]"\
   | tr "\n" "\t" | sed -e 's/i-/\ni-/g'
   echo
} 


#Instance list
ec2_cmd_ilist()
{
  aws ec2  describe-instances  --instance-ids $instance_id
} 

#Volume create from snapshot
ec2_cmd_vcre_sb()
{
#snap-00c07cffc5438b47d - 200GB
#snap-0f858b543e2ca98c7 - 8GB

#  tag_dataset="sbtest1t1M"
  tag_dataset="sbtest10t40M"

  volume_id=$(aws ec2 create-volume --region $region_id --availability-zone $az_id \
                   --snapshot-id $snapshot_id --volume-type $volume_type $volume_args --output text --query 'VolumeId' \
                   --tag-specifications "ResourceType=volume,Tags=[{Key=dataset,Value=$tag_dataset},{Key=type,Value=snapshot}]")

  echo -n "Creating volume($volume_id): "
  while state=$(aws ec2 describe-volumes --volume-ids $volume_id --output text --query 'Volumes[*].State');
        test "$state" != "available" ; do sleep 1; echo -n '.' 
  done ; echo " Done. Volume: $volume_id $state"

  aws ec2 create-tags --resources $volume_id  --tags Key=Name,Value=${tag_name} Key=iit-billing-tag,Value=${tag_iit_dev} Key=state,Value=cold
  
}

#Volume create
ec2_cmd_vcre()
{
#snap-00c07cffc5438b47d

  volume_id=$(aws ec2 create-volume --region $region_id --availability-zone $az_id $volume_args \
                                    --volume-type $volume_type --size $volume_size --output text --query 'VolumeId')

  echo -n "Creating volume: "
  while state=$(aws ec2 describe-volumes --volume-ids $volume_id --output text --query 'Volumes[*].State');
        test "$state" != "available" ; do sleep 1; echo -n '.' 
  done ; echo " Done. Volume: $volume_id $state"
  
  aws ec2 create-tags --resources $volume_id  --tags Key=Name,Value=${tag_name} Key=iit-billing-tag,Value=${tag_iit_dev}
}

#Volume attach
ec2_cmd_vatt()
{
  aws ec2 attach-volume --volume-id $volume_id --instance-id $instance_id --device /dev/sdg

  echo -n "Attaching volume: "
  while state=$(aws ec2 describe-volumes --volume-ids $volume_id --output text --query 'Volumes[*].State');
        test "$state" != "in-use" ; do sleep 1; echo -n '.' 
  done ; echo " Done. Volume: $volume_id $state"
}

#Volumes list
ec2_cmd_vlists()
{
  aws ec2 describe-volumes --output text --query 'Volumes[*].[AvailabilityZone,VolumeId,VolumeType,State,Size,Tags[*].Value]'
#  aws ec2 describe-volumes 
}

#Volume list
ec2_cmd_vlist()
{
  aws ec2 describe-volume-status --volume-ids $volume_id 
  aws ec2 describe-volumes --volume-ids $volume_id
}

#Volume detach
ec2_cmd_vdtch()
{
  aws ec2 detach-volume --volume-id $volume_id
  echo -n "Detaching volume: "
  while state=$(aws ec2 describe-volumes --volume-ids $volume_id --output text --query 'Volumes[*].State');
        test "$state" != "available" ; do sleep 1; echo -n '.' 
  done ; echo " Done. Volume: $volume_id $state"

}

#Volume delete
ec2_cmd_vdel()
{
  aws ec2 delete-volume --volume-id $volume_id
}


#Make spot request
ec2_cmd_sreq ()
{
  get_subnet
  cat spec-spot1.json | jq ".Placement.AvailabilityZone=\"$az_id\"" | sponge  spec-spot1.json
  cat spec-spot1.json | jq ".InstanceType=\"$instance_type\"" | sponge  spec-spot1.json
  cat spec-spot1.json | jq ".SubnetId=\"$subnet_id\"" | sponge  spec-spot1.json
  spot_id=$(aws ec2 request-spot-instances  --instance-count 1 --type "one-time" --spot-price "1.5" \
  --launch-specification file://spec-spot1.json --output text --query 'SpotInstanceRequests[*].SpotInstanceRequestId')
 
  echo "---------------------------------------------------------------------------------------------------------------------"
  echo -n "Requesting instance in AZ($az_id): "
  while state=$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $spot_id \
                                                        --output text --query 'SpotInstanceRequests[*].Status.Code'); 
        test "$state" != "fulfilled" ; do sleep 1; echo -n '.' 
  done ; echo " Done. Spot request $spot_id $state"
  sleep 2
  instance_id=$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids "$spot_id" --output text --query 'SpotInstanceRequests[*].InstanceId')

  echo -n "Starting instance: "
  while state=$(aws ec2 describe-instances --instance-ids $instance_id --output text --query 'Reservations[*].Instances[*].State.Name');
        test "$state" != "running" ; do sleep 1; echo -n '.' 
  done ; echo " Done. Instance $instance_id $state"

  ec2_cmd_igetip

  aws ec2 create-tags --resources $instance_id  --tags Key=cluster_name,Value=$cluster_name   Key=itype,Value=cluster_node Key=Name,Value=${tag_name} Key=iit-billing-tag,Value=${tag_iit_dev}
  
  instance_vol_id=$(aws ec2 describe-instances --instance-ids $instance_id --output text --query 'Reservations[*].Instances[*].BlockDeviceMappings[*].Ebs.VolumeId')
  aws ec2 create-tags --resources $instance_vol_id  --tags Key=Name,Value=${tag_name} Key=iit-billing-tag,Value=${tag_iit_dev}
  
}
                                                        

#batch: spot req + attach created volume or create new one from snapshot
ec2_cmd_batch1()
{
  ec2_cmd_sreq
 
  echo "aws ec2 describe-volumes --filters \"Name=tag:dataset,Values=$volume_dataset\" \
                                        Name=\"availability-zone\",Values=\"$az_id\" Name=\"size,Values=$volume_size\" \
                                        Name=\"status,Values=available\" Name=\"volume-type,Values=$volume_type\" --output text --query 'Volumes[*].VolumeId'"
                                        
  volume_ids=$(aws ec2 describe-volumes --filters "Name=tag:dataset,Values=$volume_dataset" \
                                      Name="availability-zone",Values="$az_id" Name="size,Values=$volume_size" \
                                      Name="status,Values=available" Name="volume-type,Values=$volume_type" --output text --query 'Volumes[*].VolumeId')
 
  volume_id=`echo $volume_ids | cut -f1 -d' '`
  if [ -z "$volume_id" ]; then 
    ec2_cmd_vcre_sb
  else
    echo "Found($volume_ids) and using available EBS volume in requested AZ($az_id): $volume_id"
    #ec2_cmd_vlist
  fi      
  ec2_cmd_vatt
}

#batch: del volume
ec2_cmd_batch2()
{
  ec2_cmd_idel
#  ec2_cmd_vdtch
#  ec2_cmd_vdel
}

#Volume - change volume property that it will be delete on instance termination
ec2_cmd_mod_vterm()
{
  aws ec2 modify-instance-attribute --instance-id $instance_id --block-device-mappings "[{\"DeviceName\": \"/dev/sdg\",\"Ebs\":{\"DeleteOnTermination\":true}}]"
}

#batch: enable del vol on termination + del instance
ec2_cmd_batch3()
{
  ec2_cmd_mod_vterm
  ec2_cmd_idel
}

#create cluster 
ec2_cmd_batch4()
{
  CLUSTERIP=""
  az_id="us-east-1"${NODE_LIST[0]}
  ec2_cmd_batch1
  CLUSTER_IP="$instance_id_priv_ip"
  CLUSTER_ID="$instance_id"

  az_id="us-east-1"${NODE_LIST[1]}
  ec2_cmd_batch1
  CLUSTER_IP="$CLUSTER_IP#$instance_id_priv_ip"
  CLUSTER_ID="$CLUSTER_ID $instance_id"

  az_id="us-east-1"${NODE_LIST[2]}
  ec2_cmd_batch1
  CLUSTER_IP="$CLUSTER_IP#$instance_id_priv_ip"
  CLUSTER_ID="$CLUSTER_ID $instance_id"
  echo "Created cluster: $cluster_name, IPs: $CLUSTER_IP"


  instances_ready="" 
  
  echo -n "Starting instances: "
  while [ $(echo "$instances_ready" | wc -l) -ne 3  ];  do 
  
  instances_ready=`aws ec2 describe-instance-status --instance-ids $CLUSTER_ID \
                                   --filters "Name=instance-status.reachability,Values=passed" "Name=instance-status.status,Values=ok" \
                                             "Name=system-status.reachability,Values=passed" "Name=system-status.status,Values=ok" \
                                   --output text --query  'InstanceStatuses[*].InstanceId' | grep -o "i-[[:alnum:]]*"`
  sleep 1 ; echo -n "."
  done
  echo 
  echo "Instances ready: $instances_ready"

}

#delete cluster
ec2_cmd_batch5()
{
   instance_ids=(`aws ec2  describe-instances --filters "Name=tag:cluster_name,Values=$cluster_name"  \
                                                        "Name=instance-state-name,Values=running,stopping,stopped" \
                                                        --output text --query 'Reservations[*].Instances[*].InstanceId'`)
   if [ -n "$instance_ids" ]; then 
   for instance_id in "${instance_ids[@]}"
   do 
     if [ "$CMD" == "delete_cluster" ]; then 
       ec2_cmd_batch2
     elif [ "$CMD" == "delete_cluster_full" ]; then 
       ec2_cmd_batch3
     fi
   done
   fi
}


#cat spec-spot1.json | jq '.Placement.AvailabilityZone="r5"' | sponge spec-spot1.json


while test $# -gt 0; do
  case "$1" in
  -r=*)
    region_id=$(echo "$1" | sed -e "s;-r=;;")   ;;
  -a=*)
    az_id=$(echo "$1" | sed -e "s;-a=;;")   ;;
  -azs=*)
    azs_id=$(echo "$1" | sed -e "s;-azs=;;")   ;;
  -v=*)
    volume_id=$(echo "$1" | sed -e "s;-v=;;")   ;;
  -vt=*)
    volume_type=$(echo "$1" | sed -e "s;-vt=;;")   ;;
  -vi=*)
    volume_iops=$(echo "$1" | sed -e "s;-vi=;;")   ;;
  -vs=*)
    volume_size=$(echo "$1" | sed -e "s;-vs=;;")   ;;
  -i=*)
    instance_id=$(echo "$1" | sed -e "s;-i=;;")   ;;
  -it=*)
    instance_type=$(echo "$1" | sed -e "s;-it=;;")   ;;
  -s=*)
    spot_id=$(echo "$1" | sed -e "s;-s=;;") ;;
  -sn=*)
    snapshot_id=$(echo "$1" | sed -e "s;-sn=;;") ;;
  -cn=*)
    cluster_name=$(echo "$1" | sed -e "s;-cn=;;") ;;
  -c=*)
    CMD=$(echo "$1" | sed -e "s;-c=;;") ;;
  -- )  shift; break ;;
  --*) echo "Unrecognized option: $1" ; usage ;;
    * ) break ;;  
  esac
  shift
done


region_id=${region_id:-"us-east-1"}
vpc_id=${vpc_id:-"vpc-aba20dce"}
#snap-00c07cffc5438b47d - 200GB
#snap-0f858b543e2ca98c7 - 8GB
snapshot_id=${snapshot_id:-snap-00c07cffc5438b47d}
#snapshot_id=${snapshot_id:-snap-0f858b543e2ca98c7}

volume_type=${volume_type:-gp2} volume_size=${volume_size:-8}
volume_dataset=${volume_dataset:-sbtest10t40M}
cluster_name=${cluster_name:-pxc_perf}
volume_iops=${volume_iops:-10000}

tag_iit_dev="dev-vadim-io-perf"
tag_name="Alexey_pxc_perf"


NODE_LIST=(b c d)
if [ -n "$azs_id" ]; then 
  NODE_LIST=(${azs_id//,/ })
fi
    
echo "$region_id $vpc_id"      

  if [ -n "$volume_type" -a "$volume_type" == "io1" ]; then 
    volume_args="--iops $volume_iops"
  fi


if [ -z "$az_id" -a  \( "$CMD" == "sreq" -o "$CMD" == "vcre_sb" -o "$CMD" == "create_node" -o "$CMD" == "vcre" \) ]; then 
  usage "Specify az_id with -a "
fi

if [ -z "$instance_type" -a  \( "$CMD" == "sreq" -o "$CMD" == "create_node"  -o "$CMD" == "create_cluster" \) ]; then
  usage "Specify instance_type with -it "
fi
    

if [ -z "$instance_id" -a  \( "$CMD" == "igetip" -o "$CMD" == "idel"  -o "$CMD" == "vatt" -o "$CMD" == "delete_node" -o "$CMD" == "delete_node_full" \) ]; then 
  usage "Specify instance_id with -i "
fi

if [ -z "$volume_id" -a  \( "$CMD" == "vlist" -o "$CMD" == "vdel"  -o "$CMD" == "vdtch"  \) ]; then 
  usage "Specify volume_id with -v "
fi

if [ -z "$spot_id" -a  \( "$CMD" == "sget" -o "$CMD" == "sgetip"  \) ]; then 
  usage "Specify spot_id with -s "
fi

get_subnet

          
if [ "$CMD" == "sreq" ]; then  ec2_cmd_sreq  ; fi 

if [ "$CMD" == "sget" ]; then ec2_cmd_sget ; fi 

if [ "$CMD" == "slist" ]; then ec2_cmd_slist ; fi 

if [ "$CMD" == "sgetip" ]; then ec2_cmd_sgetip ; fi 

if [ "$CMD" == "igetip" ]; then ec2_cmd_igetip ; fi 

if [ "$CMD" == "idel" ]; then ec2_cmd_idel ; fi 

if [ "$CMD" == "ilists" ]; then ec2_cmd_ilists ; fi 
if [ "$CMD" == "ilist" ]; then ec2_cmd_ilist ; fi 

if [ "$CMD" == "vcre_sb" ]; then ec2_cmd_vcre_sb ; fi 
if [ "$CMD" == "vcre" ]; then ec2_cmd_vcre ; fi 

if [ "$CMD" == "vatt" ]; then ec2_cmd_vatt ; fi 

if [ "$CMD" == "vlists" ]; then ec2_cmd_vlists ; fi 

if [ "$CMD" == "vlist" ]; then ec2_cmd_vlist ; fi 

if [ "$CMD" == "vdtch" ]; then ec2_cmd_vdtch ; fi 

if [ "$CMD" == "vdel" ]; then ec2_cmd_vdel ; fi 

if [ "$CMD" == "create_node" ]; then ec2_cmd_batch1 ; fi 
if [ "$CMD" == "create_cluster" ]; then ec2_cmd_batch4 ; fi 
if [ "$CMD" == "delete_node" ]; then ec2_cmd_batch2 ; fi 
if [ "$CMD" == "delete_node_full" ]; then ec2_cmd_batch3 ; fi 

if [ "$CMD" == "delete_cluster" -o "$CMD" == "delete_cluster_full" ]; then ec2_cmd_batch5 ; fi 

                                                        
if [ "$CMD" == "clists" ]; then ec2_cmd_clists ; fi 
if [ "$CMD" == "clist" ]; then ec2_cmd_clist ; fi
