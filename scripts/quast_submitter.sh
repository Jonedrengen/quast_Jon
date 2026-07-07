#!/bin/bash

function usage {
    echo "Usage essential: $0 -i <input_folder> -s [sample_list] -o <output_dir>"
    echo "  -i: Path to the input folder containing sample files (e.g., FASTQ files)"
    echo "  -s: Path to the sample list file (txt file with samplename pr. line) (optional but recommended)"
    echo "  -o: Path to the output directory where results will be stored"
    echo 
    echo "Usage optional"
    echo "  -m: Mode of operation ('SLURM' or 'LOCAL'),        default = 'SLURM'"
    echo "  -j: Jobname,                                       default = 'shovill_runner' "
    echo "  -c: config                                         default = 'local config on ugerm' "
    echo
    echo "avoid spaces, dots, and special characters in sample names to prevent issues with file handling"
}


while getopts "i:s:o:m:j:c:" opt; do
  case $opt in
    i) input_folder="$OPTARG" ;;
    s) sample_list="$OPTARG" ;;
    o) output_dir="$OPTARG" ;;
    m) mode="$OPTARG" ;;
    j) jobname="$OPTARG" ;;
    c) config="$OPTARG";;
    \?) echo "Invalid option -$OPTARG" >&2 ;;
  esac
done


if [[ ! -d "$input_folder" ]] || [[ ! -d "$output_dir" ]];
then
    echo "found no input folder or output folder"
    echo "__________________________________________________________"
    usage
    exit 1
fi


