# QUAST

This repository contains helper scripts and reference material for working with QUAST, a genome assembly quality assessment tool. It is intended to collect local workflow pieces for running QUAST analyses and organizing the resulting assembly evaluation outputs.

all credit goes to the quast devs at: https://github.com/ablab/quast 

## SETUP

only arm64 on mac m3 tested
´´´bash
conda env create -f env_arm64.yml
conda activate quast_JOSS
cd quast
./setup.py install
´´´

verify quast installation.
´´´bash
quast.py
´´´