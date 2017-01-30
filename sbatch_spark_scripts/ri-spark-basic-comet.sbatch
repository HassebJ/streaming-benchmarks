#/bin/bash
#SBATCH --output="spark-basic-comet.%j.%N.out"
#SBATCH --partition=compute
#SBATCH --nodes=33
#SBATCH --ntasks-per-node=24
#SBATCH --export=ALL
#SBATCH -t 02:00:00
#SBATCH --mail-user=lu.932@osu.edu
#SBATCH --mail-type=ALL
#SBATCH -A ddp132

set -o xtrace

export WORKDIR=`pwd`

#this load on 7 nodes produces 100k net
load=14286

WORKER_MEM_SPARK="10g"
DAEMON_MEM_SPARK="2g"
WORKER_CORES_SPARK=`grep "core id" /proc/cpuinfo | wc -l`
SSD_PATH_BASE=/scratch/
node_offset=2
num_zk=2
num_kafka=3
num_spark=4
num_redis=1
#--------------------------------

BENCHMARK_HOME=$(readlink -f $WORKDIR/..)
echo $BENCHMARK_HOME
HIBENCH_HOME=$BENCHMARK_HOME/../HiBench
CONF_SPARK_DEFAULT=$WORKDIR/spark_release_confs/spark
CONF_BENCHMARK=$BENCHMARK_HOME/conf
CONF_SPARK=$HIBENCH_HOME/spark-2.0.2-bin-hadoop2.7
#CONF_STORM=$BENCHMARK_HOME/apache-storm-1.0.1/conf
CONF_STORM=/var/tmp/apache-storm-1.0.1/conf
CONF_FLINK=$BENCHMARK_HOME/flink-1.0.3/conf
CONF_KAFKA=$BENCHMARK_HOME/kafka_2.10-0.8.2.1/config


reset (){
    cd $BENCHMARK_HOME
    rm *.out
#    rm ~/myhostnames
    rm -rf $BENCHMARK_HOME/kafka_2.10-0.8.2.1/
    rm -rf $BENCHMARK_HOME/spark-2.0.2-bin-hadoop2.6/
    rm -rf $BENCHMARK_HOME/apache-storm-0.9.7/
    tar -xvf $BENCHMARK_HOME/download-cache/spark-2.0.2-bin-hadoop2.6.tgz
    tar -xvf $BENCHMARK_HOME/download-cache/kafka_2.10-0.8.2.1.tgz 
    tar -xvf $BENCHMARK_HOME/download-cache/apache-storm-0.9.7.tar.gz

}
reset_all () {
    execute_all "cd ./sbatch_spark_scripts;  ./ri-spark-basic-comet.sbatch reset"
}

write_hosts_to_file () {
    rm ~/myhostnames
    ib_enabled=$1

    if [ "$ib_enabled" == "y" ];
    then
        sed -i -e "s/#host.name=\.*/host.name=\.*/g" $CONF_KAFKA/server.properties
        node_name_suffix="-ib"
    else
        sed -i -e "s/^host.name=\.*/#host.name=\.*/g" $CONF_KAFKA/server.properties
        node_name_suffix=""
    fi

    for ip_addr in `scontrol show hostnames`; do
        echo $ip_addr$node_name_suffix >> ~/myhostnames 
    done

    if [ ! -f $HOME/myhostnames ]
    then
        echo "Please create $HOME/myhostnames!"
        #scontrol show hostnames > $HOME/myhostnames
        #exit 1
       if [ "$ib_enabled" == "y" ];
       then
            sed -i -e "s/$/-ib/g" $HOME/myhostnames
       else
            sed -i -e "s/-ib//g" $HOME/myhostnames
       fi
    fi
  
}

get_master_host () {

    orig_master=`cat ~/myhostnames | head -1`
    master=$orig_master"$node_name_suffix"

    echo "got the master's hostname: $master"
}
#start zk servers
start_zk () {
    truncate -s 0 $CONF_BENCHMARK/../nohup.out 
    for ip_addr in `cat $CONF_BENCHMARK/zk`; do
        ssh -t $ip_addr "killall -9 java; cd $BENCHMARK_HOME; nohup ./ri-stream-bench.sh START_ZK"
        echo $ip_addr
    done
    cat $CONF_BENCHMARK/../nohup.out
}
#start redis
start_redis () {
    redis_host=`cat $CONF_BENCHMARK/benchmarkConf.yaml | grep redis | awk -F: '{print $2 }' | sed -r 's/\"|\s//g'`
    ssh -t $redis_host "cd $BENCHMARK_HOME; ./ri-stream-bench.sh START_REDIS"
}

replace_ip () {
   sed -i -e "s/$1.*/$1$2/g" $3
}

#start_kafka_wo_topic on seperate folders
start_kafka_wo_topic () {
    let "counts=1"
    command="./ri-stream-bench.sh START_KAFKA_WO_TOPIC $1"
    for ip_addr in `cat $CONF_BENCHMARK/kafka`; do
        echo $ip_addr
        truncate -s 0 /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka-wo-topic.out
        replace_ip host.name= $ip_addr /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka_2.10-0.8.2.1/config/server.properties
        ssh -t $ip_addr "cd /home/javed.19/git-pull/$counts/streaming-benchmarks ; nohup $command >> /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka-wo-topic.out" 
        ((counts+=1))
        sleep 5
    done

    let "counts=1"
    for ip_addr in `cat $CONF_BENCHMARK/kafka`; do
        cat /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka-wo-topic.out
        ((counts+=1))
    done
}


#start_kafka_wo_topic on the same directory
start_kafka_wo_topic_same () {
   # let "counts=1"
    counts="finished"
    truncate -s 0 /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka-wo-topic.out
    command="./ri-stream-bench.sh START_KAFKA_WO_TOPIC"
    for ip_addr in `cat $CONF_BENCHMARK/kafka`; do
        echo $ip_addr
       # truncate -s 0 /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka-wo-topic.out
        replace_ip host.name= $ip_addr /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka_2.10-0.8.2.1/config/server.properties
        ssh -t $ip_addr "cd /home/javed.19/git-pull/$counts/streaming-benchmarks ; nohup $command >> /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka-wo-topic.out" 
       # ((counts+=1))
        sleep 5
    done

   # let "counts=1"
   # for ip_addr in `cat $CONF_BENCHMARK/kafka`; do
        cat /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka-wo-topic.out
    #    ((counts+=1))
   # done
}

#start_kafka
start_kafka () {
    let "counts=1"
    command="./ri-stream-bench.sh START_KAFKA"
    for ip_addr in `cat $CONF_BENCHMARK/kafka`; do
        echo $ip_addr
        truncate -s 0 /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka.out
        replace_ip host.name= $ip_addr /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka_2.10-0.8.2.1/config/server.properties
        ssh -t $ip_addr "cd /home/javed.19/git-pull/$counts/streaming-benchmarks ; nohup $command >> /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka.out" 
        ((counts+=1))
        sleep 5
    done

    let "counts=1"
    for ip_addr in `cat $CONF_BENCHMARK/kafka`; do
        cat /home/javed.19/git-pull/$counts/streaming-benchmarks/kafka.out
        ((counts+=1))
    done
}

check_kafka_running () {

    for ip_addr in `cat $CONF_SPARK/conf/slaves`; do
        echo $ip_addr
 #       replace_ip host.name= $ip_addr $CONF_KAFKA/server.properties
        ssh -t $ip_addr "killall -9 java"
        ssh -t $ip_addr "ps aux | grep java"
    done 
} 

config_zk () {
    rm -rf /tmp/dev-storm-zookeeper 
    let total_zk=$1+num_zk-1
    # write zk connection string to zk hosts as it is with new line sperated
    cat ~/myhostnames | sed -n "$1,$total_zk p" > $CONF_BENCHMARK/zk

    zk_hosts=`cat ~/myhostnames | sed -n "$1,$total_zk p"`
    #ad port and " to start and end of ips 
    zk_connections=`echo $zk_hosts | sed -e "s/\s/:2181,/g" | sed -e "s/$/:2181\"/" | sed -e "s/^/\"/"`
    zk_connections_wo_port=`echo $zk_hosts | sed -e "s/\s/,/g" | sed -e "s/$/\"/" | sed -e "s/^/\"/"`
    #write connection string to benchmark script
    sed -i -e "s/ZK_CONNECTIONS=.*/ZK_CONNECTIONS=$zk_connections/g" $BENCHMARK_HOME/ri-stream-bench.sh
    sed -i -e "s/zookeeper.connect=.*/zookeeper.connect=$zk_connections/g" $CONF_KAFKA/consumer.properties
    zk_connections_wo_quote=`echo $zk_connections | sed -e "s/\"//g"`
    sed -i -e "s/zookeeper.connect=.*/zookeeper.connect=$zk_connections_wo_quote/g" $CONF_KAFKA/server.properties
    sed -i -e "s/ZK_CS_REPLACE/$zk_connections_wo_quote/g" $HIBENCH_HOME/conf/hibench.conf 
    #write connection string to benchmark benchMark.yaml
    ex $CONF_BENCHMARK/benchmarkConf.yaml -c ":%s/zookeeper.servers:\(\n\s*-\s".*"\)*/zookeeper.servers:\r    - $zk_connections/g" -c ':wq!' > tmp
    #convert cs to yaml format
    yaml_zk_connections=`echo $zk_connections_wo_port | sed -e "s/,/\"\r    - \"/g" | sed -e "s/^\"/   - \"/"`
    ex $CONF_STORM/storm.yaml -c ":%s/.*storm.zookeeper.servers:\(\n\s*-\s".*"\)*/storm.zookeeper.servers:\r $yaml_zk_connections/g" -c ':wq!' > tmp

    echo $((total_zk+1))
}

config_redis () {
    rm -f $BENCHMARK_HOME/dump.rdb
    let total_redis=$1+num_redis-1                                            
    redis_host=`cat ~/myhostnames | sed -n "$1,$total_redis p"`
    sed -i -e "s/redis.host:.*/redis.host: \"$redis_host\"/g" $CONF_BENCHMARK/benchmarkConf.yaml 
    echo $((total_redis+1)) 
}

config_kafka () {
    rm -rf /tmp/kafka-logs/
    let total_kafka=$1+num_kafka-1
    cat ~/myhostnames | sed -n "$1,$total_kafka p" > $CONF_BENCHMARK/kafka
    kafka_hosts=`cat ~/myhostnames | sed -n "$1,$total_kafka p"`
    kafka_connections=`echo $kafka_hosts | sed -e "s/\s/:9092,/g" | sed -e "s/$/:9092/"`    
    sed -i -e "s/KAFKA_BROKERS_REPLACE/$kafka_connections/" $HIBENCH_HOME/conf/hibench.conf
    sed -i -e "s/metadata.broker.list=.*/metadata.broker.list=$kafka_connections/g" $CONF_KAFKA/producer.properties
    kafka_connections=`echo $kafka_hosts | sed -e "s/\s/,/g" | sed -e "s/$/\"/" | sed -e "s/^/\"/"`
    yaml_kafka_connections=`echo $kafka_connections | sed -e "s/,/\"\r    - \"/g" | sed -e "s/^\"/   - \"/"`

    ex  $CONF_BENCHMARK/benchmarkConf.yaml -c ":%s/kafka.brokers:\(\n\s*-\s".*"\)*/kafka.brokers:\r $yaml_kafka_connections/g" -c ':wq!' > tmp
   #jugaaaar
     sed -i -e "s/ZK_CS_REPLACE/storage14:2181,storage15:2181/g" $HIBENCH_HOME/conf/hibench.conf
    echo $((total_kafka+1))
}


config_kafka_dir () {
    let "counts=1"
    for ip_addr in `cat $CONF_BENCHMARK/kafka`; do
        cd /home/javed.19/git-pull/$counts/streaming-benchmarks/sbatch_spark_scripts
        ./ri-spark-basic-comet.sbatch config_kafka 6
        ((counts+=1))
    done
    config_kafka 6
}

config_all_dir () {
    config_all 
    let "counts=1"
    for ip_addr in `cat $CONF_BENCHMARK/kafka`; do
        cd /home/javed.19/git-pull/$counts/streaming-benchmarks/sbatch_spark_scripts
        ./ri-spark-basic-comet.sbatch config_all
        ((counts+=1))
    done
   }

config_spark () {
    rm -rf /var/tmp/
    let total_spark=$1+num_spark-1
     cat ~/myhostnames | sed -n "$1,$total_spark p" > $CONF_SPARK/conf/slaves
    cp $CONF_SPARK/conf/slaves $HIBENCH_HOME/spark-2.0.2-bin-hadoop2.7/conf/
 local ib_enabled="$2"     
 if [ "$ib_enabled" = "y" ];
    then
        node_name_suffix="-ib"
    else
        node_name_suffix=""
    fi
    master=`cat ~/myhostnames | head -1`
    f_master=`echo $master | sed -e "s/-ib//g"`
    spark_master="spark:\/\/$f_master:7077"
    
    sed -i  "s/hibench.spark.master .*/hibench.spark.master          $spark_master/g" $HIBENCH_HOME/conf/spark.conf

 cd $BENCHMARK_HOME
    cp $CONF_SPARK_DEFAULT/* $CONF_SPARK/conf/
   # cp $WORKDIR/spark_release_confs/ri-stream-bench.sh $BENCHMARK_HOME
    sed -i "s|MASTER_REPLACE|$master|g" $CONF_SPARK/conf/*
    sed -i "s|MASTER_REPLACE|$master|g" $BENCHMARK_HOME/ri-stream-bench.sh
    #sed -i "s|JAVA_HOME_REPLACE|$JAVA_HOME|g" $CONF_SPARK/conf/spark-env.sh
    #sed -i "s|CONF_SPARK_REPLACE|$CONF_SPARK|g" $CONF_SPARK/conf/spark-env.sh
    #sed -i "s|CONF_SPARK_REPLACE|$CONF_SPARK|g" $CONF_SPARK/conf/spark-defaults.conf
    #sed -i "s|HADOOP_HOME_REPLACE|$HADOOP_HOME|g" $CONF_SPARK/conf/spark-env.sh
    #sed -i "s|SSD_SPARK_REPLACE|$SSD_PATH_SPARK|g" $CONF_SPARK/conf/spark-env.sh
    sed -i "s|LOCAL_IP_SUFFIX_REPLACE|$node_name_suffix|g" $CONF_SPARK/conf/spark-env.sh
    sed -i "s|WORKER_MEM_REPLACE|$WORKER_MEM_SPARK|g" $CONF_SPARK/conf/spark-env.sh
    sed -i "s|DAEMON_MEMORY_REPLACE|$DAEMON_MEM_SPARK|g" $CONF_SPARK/conf/spark-env.sh
    sed -i "s|WORKER_MEM_REPLACE|$WORKER_MEM_SPARK|g" $CONF_SPARK/conf/spark-defaults.conf
    sed -i "s|WORKER_CORE_REPLACE|$WORKER_CORES_SPARK|g" $CONF_SPARK/conf/spark-env.sh
    #sed -i "s|SPARK_IB_ENABLED_REPLACE|$IB_ENABLED|g" $CONF_SPARK/conf/spark-defaults.conf
    #sed -i "s|HADOOP_IB_ENABLED_REPLACE|$IB_ENABLED|g" $CONF_SPARK/conf/spark-defaults.conf
    


   echo $((total_spark+1))
}

config_storm(){
ib_enabled=$1     
 if [ "$ib_enabled" = "y" ];
    then
        node_name_suffix="-ib"
    else
        node_name_suffix=""
    fi
 orig_master=`cat ~/myhostnames | head -1`
    master=$orig_master"$node_name_suffix"
     sed -i -e "s/.*storm.local.hostname:.*/#storm.local.hostname: \"$HOSTNAME\"/g" $CONF_STORM/storm.yaml

   
    sed -i -e "s/hibench.streambench.storm.nimbus .*/hibench.streambench.storm.nimbus        $master/g" $HIBENCH_HOME/conf/storm.conf                                                 
    storm_hosts=`cat $CONF_SPARK/conf/slaves`
    storm_connections=`echo $storm_hosts | sed -e "s/\s/:9092,/g" | sed -e "s/$/:9092/"`    
    storm_connections=`echo $storm_hosts | sed -e "s/\s/,/g" | sed -e "s/$/\"/" | sed -e "s/^/\"/"`
    yaml_storm_connections=`echo $storm_connections | sed -e "s/,/\"\r    - \"/g" | sed -e "s/^\"/   - \"/"`



    ex  $CONF_STORM/storm.yaml -c ":%s/supervisor.supervisors:\(\n\s*-\s".*"\)*/supervisor.supervisors:\r $yaml_storm_connections/g" -c ':wq!' > tmp
         sed -i -e "s/nimbus.seeds: .*/nimbus.seeds: \[\"$master\"\]/g" $CONF_STORM/storm.yaml
  

}


config_flink (){
ib_enabled=$1     
 if [ "$ib_enabled" = "y" ];
    then
        node_name_suffix="-ib"
    else
#        sed -i -e "s/^host.name=\.*/#host.name=\.*/g" $CONF_KAFKA/server.properties
        node_name_suffix=""
    fi
 orig_master=`cat ~/myhostnames | head -1`
    master=$orig_master

       sed -i -e "s/jobmanager.rpc.address: .*/jobmanager.rpc.address: $master/g" $CONF_FLINK/flink-conf.yaml
   echo $master > $CONF_FLINK/master
cp $CONF_SPARK/conf/slaves $CONF_FLINK/
   ip_master=`cat /etc/hosts | grep -w "$master.cluster" | gawk --field-separator=' ' '{ print $1 }'` 
   sed -i -e "s/hibench.flink.master .*/hibench.flink.master       $ip_master:6123/g" $HIBENCH_HOME/conf/flink.conf   
}

start_storm_cluster () {
    truncate -s 0 $BENCHMARK_HOME/storm-load.out
    cd $BENCHMARK_HOME
    local_ip=`hostname -s`
    #assign_storm_hostname "$1" "$local_ip"
    ./ri-stream-bench.sh START_STORM_MASTER "$1"
    sleep 2
    command="./ri-stream-bench.sh START_STORM_SLAVE $1"
    for ip_addr in `cat $CONF_SPARK/conf/slaves`; do
    # assign_storm_hostname "$1" "$ip_addr"
       ssh -t $ip_addr "cd $BENCHMARK_HOME; nohup $command >> storm-load.out"
        ((counts+=1))
    done

    cat $BENCHMARK_HOME/storm-load.out 
    

}

assign_storm_hostname(){
    if [ "$1" = "y" ];
    then
        HOSTNAME="$2"-ib
    else
        HOSTNAME="$2"
    fi
        sed -i -e "s/.*storm.local.hostname:.*/storm.local.hostname: \"$HOSTNAME\"/g" $CONF_STORM/storm.yaml

}

start_flink_cluster(){
    cd $BENCHMARK_HOME
    ./ri-stream-bench.sh START_FLINK
}


#start_spark
start_spark_cluster () {
       # ./ri-stream-bench.sh START_SPARK
         cd $HIBENCH_HOME
        ./spark-2.0.2-bin-hadoop2.7/sbin/start-all.sh

}


 
#star spark processing
start_spark_processing (){
    
    cd $BENCHMARK_HOME
    ./ri-stream-bench.sh START_SPARK_PROCESSING
}

start_data_load () {
    cd $BENCHMARK_HOME
    rm $BENCHMARK_HOME/load
#    replace_ip "LOAD:-" "$load}" $BENCHMARK_HOME/ri-stream-bench.sh                                              
   # let "count=0"
   # command="./ri-stream-bench.sh START_LOAD"
   # cat $HOME/myhostnames | tail -7 |  while read ip_addr; do                                                     
   #     ssh -t $ip_addr "cd $BENCHMARK_HOME; nohup $command >> load.out" 
   #     ((count+=17000))
   #     echo $ip_addr >> $BENCHMARK_HOME/load
   #     if [ $count -gt $1 ]; 
   #     then                                                                   
   #         break
   #     fi
   # done
   cat ~/myhostnames | tail -7 > loaders.txt
    mussh -H loaders.txt -c "cd /home/javed.19/git-pull/finished/streaming-benchmarks; ./ri-stream-bench.sh START_LOAD" -m


}

stop_data_load() {
    cat ~/myhostnames | tail -7 > loaders.txt
    mussh -H loaders.txt -c "cd /home/javed.19/git-pull/finished/streaming-benchmarks; ./ri-stream-bench.sh STOP_LOAD" -m
    #cd $BENCHMARK_HOME
    #let "count=0"
    #command="./ri-stream-bench.sh STOP_LOAD"
    #while read ip_addr; do
    #    ssh -t $ip_addr "cd $BENCHMARK_HOME; nohup $command >> unload.out"
    #    ((count+=17000))
    #    echo $ip_addr
    #    if [ $count -gt $1 ];
    #    then
    #        break
    #    fi
    #done < $BENCHMARK_HOME/load
}

config_all () {
     rm -rf /var/tmp
     node_offset=$(config_spark $node_offset)
 #   node_offset=$(config_redis $node_offset)
    node_offset=$(config_kafka $node_offset )
    node_offset=$(config_zk $node_offset)

}

execute_all () {

    let "counts=1"
    for ip_address in `cat $CONF_SPARK/conf/slaves`; do 
   # while [ $counts -lt 6 ]; do
#        $1
         ssh -t $ip_address "cd /home/javed.19/git-pull/finished/streaming-benchmarks; $1"
        ((counts+=1))
    done

}

execute_all_kafka () {

    let "counts=1"
    for ip_address in `cat $CONF_BENCHMARK/kafka`; do 
#        $1
         ssh -t $ip_address "cd /home/javed.19/git-pull/$counts/streaming-benchmarks; $1"
        ((counts+=1))
    done

}

git_update_all (){
    cd ..
    git push
    execute_all_kafka "git reset --hard; git pull"
}

run() {
  OPERATION=$1
  shift
  if [ "config_all" = "$OPERATION" ];
  then
      config_all
  elif [ "config_all_dir" = "$OPERATION" ];
  then
      config_all_dir
  elif [ "config_kafka_dir" = "$OPERATION" ];
  then
      config_kafka_dir
  elif [ "config_spark" = "$OPERATION" ];
  then
      config_spark 2 "$@"
  elif [ "config_storm" = "$OPERATION" ];
  then
      config_storm "$@"
  elif [ "config_flink" = "$OPERATION" ];
  then
      config_flink "$@"
 elif [ "config_zk" = "$OPERATION" ];
  then
      config_zk 9 
  elif [ "config_kafka" = "$OPERATION" ];
  then
      config_kafka 6 
  elif [ "iptof" = "$OPERATION" ];
  then
      write_hosts_to_file "$1"
  elif [ "git_update_all" = "$OPERATION" ];
  then
      git_update_all
  elif [ "start_zk" = "$OPERATION" ];
  then
      start_zk
  elif [ "start_redis" = "$OPERATION" ];
  then
      start_redis
  elif [ "start_kafka" = "$OPERATION" ];
  then
      start_kafka
      #check_kafka_running
  elif [ "start_kafka_wo_topic_same" = "$OPERATION" ];
  then
      start_kafka_wo_topic_same
  elif [ "start_kafka_wo_topic" = "$OPERATION" ];
  then
      start_kafka_wo_topic  "$1"
  elif [ "start_spark_cluster" = "$OPERATION" ];
  then
      start_spark_cluster   "$1"
  elif [ "start_storm_cluster" = "$OPERATION" ];
  then
      start_storm_cluster  "$1"
  elif [ "start_flink_cluster" = "$OPERATION" ];
  then
      start_flink_cluster
  elif [ "start_spark_processing" = "$OPERATION" ];
  then
      start_spark_processing
  elif [ "load_data" = "$OPERATION" ];
  then
      start_data_load $1
     # sleep $2
     # stop_data_load $1
  elif [ "stop_load" = "$OPERATION" ];
  then
    stop_data_load $1
  elif [ "kill_java" = "$OPERATION" ];
  then
    check_kafka_running
  elif [ "reset" = "$OPERATION" ];
  then
    reset
  elif [ "config_kafka_all" = "$OPERATION" ];
  then
    config_kafka_all
  elif [ "reset_all" = "$OPERATION" ];
  then
    reset_all
  elif [ "execute_all_kafka" = "$OPERATION" ];
  then
    execute_all_kafka "$1"
  elif [ "execute_all" = "$OPERATION" ];
  then
    execute_all "$1"
  elif [ "STORM_TEST" = "$OPERATION" ];
  then
    run "START_ZK"
    run "START_REDIS"
    run "START_KAFKA"
    run "START_STORM"
    run "START_STORM_TOPOLOGY"
    run "START_LOAD"
    sleep $TEST_TIME
    run "STOP_LOAD"
    run "STOP_STORM_TOPOLOGY"
    run "STOP_STORM"
    run "STOP_KAFKA"
    run "STOP_REDIS"
    run "STOP_ZK"
  fi
}

if [ $# -lt 1 ];
then
 run "HELP"
 #reset
else
    run "$@"
fi
