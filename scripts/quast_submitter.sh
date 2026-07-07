#!/bin/bash




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

