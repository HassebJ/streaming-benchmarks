#/bin/bash
#set -o xtrace
#SBATCH --output="spark-basic-comet.%j.%N.out"
#SBATCH --partition=compute
#SBATCH --nodes=33
#SBATCH --ntasks-per-node=24
#SBATCH --export=ALL
#SBATCH -t 02:00:00
#SBATCH --mail-user=lu.932@osu.edu
#SBATCH --mail-type=ALL
#SBATCH -A ddp132

export WORKDIR=`pwd`

load=$1
ib_enabled=$2
# CHANGE HERE : cluster specific
#--------------------------------

if [ "$ib_enabled" == "y" ];
then 
    node_name_suffix="-ib"
else
    node_name_suffix=""
fi


WORKER_MEM_SPARK="96g"
DAEMON_MEM_SPARK="2g"
WORKER_CORES_SPARK=`grep "core id" /proc/cpuinfo | wc -l`
SSD_PATH_BASE=/scratch/
node_offset=1
num_zk=3
num_kafka=2
num_spark=3
num_redis=1
#--------------------------------

BENCHMARK_HOME=$(readlink -f $WORKDIR/..)
echo $BENCHMARK_HOME
CONF_SPARK_DEFAULT=$WORKDIR/spark_release_confs/spark
CONF_BENCHMARK=$BENCHMARK_HOME/conf
CONF_SPARK=$BENCHMARK_HOME/spark-2.0.2-bin-hadoop2.6
CONF_STORM=$BENCHMARK_HOME/apache-storm-0.9.7/conf
CONF_FLINK=
CONF_KAFKA=$BENCHMARK_HOME/kafka_2.10-0.8.2.1/config

rm ~/myhostnames

for ip_addr in `scontrol show hostnames`; do
    echo $ip_addr$node_name_suffix >> ~/myhostnames 
done


#set master and slave addresses
if [ ! -f $HOME/myhostnames ]
then
  echo "Please create $HOME/myhostnames!"
  #scontrol show hostnames > $HOME/myhostnames
  exit 1
fi
orig_master=`cat ~/myhostnames | head -1`
master=$orig_master"$node_name_suffix"

echo "got the master's hostname: $master"

#start zk servers
start_zk () {

    for ip_addr in `cat $CONF_BENCHMARK/zk`; do
        ssh -t $ip_addr "killall -9 java; cd $BENCHMARK_HOME; nohup ./ri-stream-bench.sh START_ZK"
        echo $ip_addr
    done

}
#start redis
start_redis () {
    redis_host=`cat $CONF_BENCHMARK/benchmarkConf.yaml | grep redis | awk -F: '{print $2 }' | sed -r 's/\"|\s//g'`
    ssh -t $redis_host "cd $BENCHMARK_HOME; ./ri-stream-bench.sh START_REDIS"
}

replace_ip () {
   sed -i -e "s/$1.*/$1$2/g" $3
}

#start_kafka
start_kafka () {

    for ip_addr in `cat $CONF_BENCHMARK/kafka`; do
        echo $ip_addr
        replace_ip host.name= $ip_addr $CONF_KAFKA/server.properties
        ssh -t $ip_addr "cd $BENCHMARK_HOME; ./ri-stream-bench.sh START_KAFKA"  
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
    #write connection string to benchmark benchMark.yaml
    ex $CONF_BENCHMARK/benchmarkConf.yaml -c ":%s/zookeeper.servers:\(\n\s*-\s".*"\)*/zookeeper.servers:\r    - $zk_connections/g" -c ':wq!' > tmp
    #convert cs to yaml format
    yaml_zk_connections=`echo $zk_connections_wo_port | sed -e "s/,/\"\r    - \"/g" | sed -e "s/^\"/   - \"/"`
    ex $CONF_STORM/storm.yaml -c ":%s/storm.zookeeper.servers:\(\n\s*-\s".*"\)*/storm.zookeeper.servers:\r $yaml_zk_connections/g" -c ':wq!' > tmp

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
    sed -i -e "s/metadata.broker.list=.*/metadata.broker.list=$kafka_connections/g" $CONF_KAFKA/producer.properties
    kafka_connections=`echo $kafka_hosts | sed -e "s/\s/,/g" | sed -e "s/$/\"/" | sed -e "s/^/\"/"`
    yaml_kafka_connections=`echo $kafka_connections | sed -e "s/,/\"\r    - \"/g" | sed -e "s/^\"/   - \"/"`

    ex  $CONF_BENCHMARK/benchmarkConf.yaml -c ":%s/kafka.brokers:\(\n\s*-\s".*"\)*/kafka.brokers:\r $yaml_kafka_connections/g" -c ':wq!' > tmp
    echo $((total_kafka+1))
}

config_spark () {
    let total_spark=$1+num_spark-1
    cat ~/myhostnames | sed -n "$1,$total_spark p" > $CONF_SPARK/conf/slaves
    echo $((total_spark+1))
}

#start_spark
start_spark_cluster () {
    cd $BENCHMARK_HOME
    cp $CONF_SPARK_DEFAULT/* $CONF_SPARK/conf/
    sed -i "s|MASTER_REPLACE|$master|g" $CONF_SPARK/conf/*
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
    
    ./ri-stream-bench.sh START_SPARK
}
 
#star spark processing
start_spark_processing (){
    
    cd $BENCHMARK_HOME
    ./ri-stream-bench.sh START_SPARK_PROCESSING
}

start_data_load () {
    cd $BENCHMARK_HOME
    replace_ip "LOAD:-" "$load}" $BENCHMARK_HOME/ri-stream-bench.sh                                              
    let "count=0"
    while read ip_addr; do                                                     
        ssh -t $ip_addr "cd $BENCHMARK_HOME; ./ri-stream-bench.sh START_LOAD"   
        ((count+=17000))
        echo $ip_addr
        if [ $count -gt $load ]; 
        then                                                                   
            break
        fi
    done < $HOME/myhostnames 
}

stop_data_load() {
    cd $BENCHMARK_HOME
    let "count=0"
    while read ip_addr; do
        ssh -t $ip_addr "cd $BENCHMARK_HOME; ./ri-stream-bench.sh STOP_LOAD"   
        ((count+=17000))
        echo $ip_addr
        if [ $count -gt $load ];
        then
            break
        fi
    done < $HOME/myhostnames
}

run () {
   node_offset=$(config_spark $node_offset)
   node_offset=$(config_redis $node_offset)
   node_offset=$(config_kafka $node_offset)
   node_offset=$(config_zk $node_offset)

}

#run
#start_zk
#start_redis
#start_kafka
start_spark_cluster
start_spark_processing
#start_data_load
#sleep 100
#stop_data_load
