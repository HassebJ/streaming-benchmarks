#!/bin/bash 


eth_bench (){
	local ntwrk_name=$1
	local bench_name=$2
	local framework_name=$3


	cd /home/javed.19/git-pull/finished/streaming-benchmarks/sbatch_spark_scripts
	./ri-spark-basic-comet.sbatch iptof n
	./ri-spark-basic-comet.sbatch config_all
	./ri-spark-basic-comet.sbatch config_all_dir
	./hadoop-script.sh

	cd /home/javed.19/git-pull/finished/HiBench
	bin/workloads/streaming/$bench_name/prepare/genSeedDataset.sh

	cd /home/javed.19/git-pull/finished/streaming-benchmarks/sbatch_spark_scripts
	./ri-spark-basic-comet.sbatch start_zk
	./ri-spark-basic-comet.sbatch start_kafka_wo_topic eth
	./ri-spark-basic-comet.sbatch config_kafka

	./ri-spark-basic-comet.sbatch config_spark n

	if [[ $framework_name = "spark" ]]; then
		./ri-spark-basic-comet.sbatch start_spark_cluster
	elif [[ $framework_name = "storm" ]]; then
		./ri-spark-basic-comet.sbatch config_storm n
		./ri-spark-basic-comet.sbatch execute_all "./ri-spark-basic-comet.sbatch config_storm n"
		#    ./ri-spark-basic-comet.sbatch start_storm_cluster n 
		export STORM_HOME=/var/tmp/apache-storm-1.0.1
	elif [[ $framework_name = "flink" ]]; then
		./ri-spark-basic-comet.sbatch config_flink n
		./ri-spark-basic-comet.sbatch start_flink_cluster
	fi
	mkdir /var/tmp/hibench-logs
	log_name="$ntwrk_name"-"$bench_name"-"$framework_name".out
	./ri-spark-basic-comet.sbatch execute_all "sar -n DEV 2 840 > /var/tmp/hibench-logs/$log_name  &"

	cd /home/javed.19/git-pull/finished/HiBench
	generate_data_benchmark=bin/workloads/streaming/$bench_name/prepare/dataGen.sh
	start_framework_processing=bin/workloads/streaming/$bench_name/$framework_name/run.sh

	$generate_data_benchmark & 
	sleep 2
	$start_framework_processing && fg
}
#<<<<<<<<<<<<<<<<<<<<<<<<<<<<IPOIB>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
ipoib_bench(){
	local ntwrk_name=$1
	local bench_name=$2
	local framework_name=$3

	cd /home/javed.19/git-pull/finished/streaming-benchmarks/sbatch_spark_scripts
	./ri-spark-basic-comet.sbatch iptof y
	./ri-spark-basic-comet.sbatch config_all_dir
	./hadoop-script.sh
	cd /home/javed.19/git-pull/finished/HiBench
	bin/workloads/streaming/$bench_name/prepare/genSeedDataset.sh

	cd /home/javed.19/git-pull/finished/streaming-benchmarks/sbatch_spark_scripts
	./ri-spark-basic-comet.sbatch iptof n
	./ri-spark-basic-comet.sbatch config_zk
	./ri-spark-basic-comet.sbatch start_zk

	./ri-spark-basic-comet.sbatch iptof y
	./ri-spark-basic-comet.sbatch config_spark
	./hadoop-script.sh config
	./ri-spark-basic-comet.sbatch config_kafka_dir

	./ri-spark-basic-comet.sbatch start_kafka_wo_topic ib


	./ri-spark-basic-comet.sbatch config_spark y

	if [[ $framework_name = "spark" ]]; then
		./ri-spark-basic-comet.sbatch start_spark_cluster
	elif [[ $framework_name = "storm" ]]; then
		./ri-spark-basic-comet.sbatch config_storm y
		# ./ri-spark-basic-comet.sbatch start_storm_cluster y
		./ri-spark-basic-comet.sbatch config_storm y    
		./ri-spark-basic-comet.sbatch execute_all "./ri-spark-basic-comet.sbatch config_storm y" 
		export STORM_HOME=/var/tmp/apache-storm-1.0.1
	elif [[ $framework_name = "flink" ]]; then
		./ri-spark-basic-comet.sbatch config_flink y
		./ri-spark-basic-comet.sbatch start_flink_cluster
	fi

	mkdir /var/tmp/hibench-logs
	log_name="$ntwrk_name"-"$bench_name"-"$framework_name".out
	./ri-spark-basic-comet.sbatch execute_all "sar -n DEV 2 840 > /var/tmp/hibench-logs/$log_name  &"



	cd /home/javed.19/git-pull/finished/HiBench
	generate_data_benchmark=bin/workloads/streaming/$bench_name/prepare/dataGen.sh
	start_framework_processing=bin/workloads/streaming/$bench_name/$framework_name/run.sh

	$generate_data_benchmark & 
	sleep 2
	$start_framework_processing && fg
	# PID=$!
	# sleep 21m

	# kill $PID

}

run() {
	OPERATION=$1
	# shift
	if [ "ib" = "$OPERATION" ];
	then
		ipoib_bench "$@"
	elif [ "eth" = "$OPERATION" ];
	then
		eth_bench "$@"
	fi
}

if [ $# -lt 1 ];
then
	echo "need three arguments"
	#reset
else
	run "$@"
fi
