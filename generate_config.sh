#!/bin/bash --login

for v in "$GLOBAL_BATCH" "$MICRO_BATCH" "$GRAD_ACC_STEPS" "$ZERO_STAGE" \
         "$PP" "$DTYPE"
do
  if [ -z $v ]; then
    echo "Please export required envs before execute $0"
    exit 1
  fi
done

if [ $# -ne 1 ]; then
  echo "Usage: $0 config_file"
  exit 1
fi

# \"optimizer\": {
#   \"type\": \"AdamW\",
#   \"params\": {
#     \"lr\": ${LR},
#     \"beta1\": 0.9,
#     \"beta2\": 0.95,
#     \"eps\": 1e-5,
#     \"weight_decay\": 1e-1
#   }
# },
# \"scheduler\": {
#   \"type\": \"WarmupLR\",
#   \"params\": {
#       \"warmup_min_lr\": 0.00003,
#       \"warmup_max_lr\": 0.0003,
#       \"warmup_num_steps\": 5000
#   }
# },

extra=""
common="\
    \"train_batch_size\": $GLOBAL_BATCH,
    \"train_micro_batch_size_per_gpu\": $MICRO_BATCH,
    \"steps_per_print\": 1,
    \"gradient_accumulation_steps\": $GRAD_ACC_STEPS,
    \"zero_allow_untested_optimizer\": true,
    \"gradient_clipping\": 1.0,
    \"activation_checkpointing\": {
      \"partition_activations\": true,
      \"contiguous_memory_optimization\": false
    },
    \"wall_clock_breakdown\": false,"

flops_profiler="\
    \"flops_profiler\": {
      \"enabled\": true,
      \"profile_step\": 4,
      \"module_depth\": -1,
      \"top_modules\": 1,
      \"detailed\": true,
      \"output_file\": null
    }"

if [[ $DTYPE == "bf16" ]]; then
dtype="\
    \"communication_data_type\": \"bfp16\",
    \"fp16\": {
      \"enabled\": false,
      \"loss_scale\": 0,
      \"loss_scale_window\": 1000,
      \"hysteresis\": 2,
      \"min_loss_scale\": 1
    },
    \"bfloat16\": {
      \"enabled\": true,
      \"loss_scale\": 1.0
    },"
elif [[ $DTYPE == "fp16" ]]; then
dtype="\
    \"communication_data_type\": \"fp16\",
    \"fp16\": {
      \"enabled\": true,
      \"loss_scale\": 0,
      \"loss_scale_window\": 1000,
      \"hysteresis\": 2,
      \"min_loss_scale\": 1
    },
    \"bfloat16\": {
      \"enabled\": false,
      \"loss_scale\": 1.0
    },"
else
  dtype="\"communication_data_type\": \"fp32\","
fi

if [ $ZERO_STAGE == 3 ]; then
zero="\
    \"zero_optimization\": {
      \"stage\": 3,
      \"reduce_scatter\": false,
      \"mics_shard_size\": 4,
      \"mics_hierarchical_params_gather\": true,
      \"stage3_max_live_parameters\": 3e9,
      \"stage3_max_reuse_distance\": 3e9,
      \"stage3_param_persistence_threshold\": 1e5,
      \"stage3_prefetch_bucket_size\": 5e7,
      \"contiguous_gradients\": true,
      \"overlap_comm\": true,
      \"reduce_bucket_size\": 90000000,
      \"sub_group_size\": 1e9,
      \"offload_optimizer\": {
        \"device\": \"none\",
        \"buffer_count\": 4,
        \"pipeline_read\": false,
        \"pipeline_write\": false,
        \"pin_memory\": true
      }
    },"

# elif [[ $ZERO_STAGE == 2 ]]; then
elif [ "${ZERO_STAGE}" == 2 ] || [ "${ZERO_STAGE}" == 1 ]; then

if [[ -n "${CPU_OPTIMIZER}" ]]; then
echo "!!!! CAUGHT CPU_OPTIMIZER !!!!"

zero="\
    \"zero_optimization\": {
        \"stage\": $ZERO_STAGE,
        \"offload_optimizer\": {
          \"device\": \"cpu\"
        }
    },"

else
zero="\
    \"zero_optimization\": {
      \"stage\": $ZERO_STAGE
    },"
fi

# elif [[ $ZERO_STAGE == 1 ]]; then
if [[ $PP > 1 ]]; then
  extra="\
      \"data_types\": {
        \"grad_accum_dtype\": \"fp32\"
      },
      \"comms_logger\": {
        \"enabled\": true,
        \"verbose\": false,
        \"prof_all\": true,
        \"debug\": false
      },"
else
  # echo 'please add the config for zero_stage 1 without pipeline-parallelism'
  extra="\
      \"comms_logger\": {
        \"enabled\": true,
        \"verbose\": false,
        \"prof_all\": true,
        \"debug\": false
      },"
fi
else
  echo 'Please add the correct config set!!!'
fi

# flops_profiler must at the end because no ',' is allowed at the end
cat <<EOT > $1
{
$common
$zero
$dtype
$extra
$flops_profiler
}
EOT
