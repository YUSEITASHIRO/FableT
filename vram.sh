#!/bin/bash
ssh g24 "nvidia-smi --query-gpu=memory.free,memory.used,memory.total --format=csv,noheader,nounits | awk -F, '{printf \"FREE %d GiB / USED %d GiB / TOTAL %d GiB\n\", \$1/1024, \$2/1024, \$3/1024}'; echo '--- who is using VRAM ---'; nvidia-smi --query-compute-apps=pid,used_memory,process_name --format=csv,noheader"
