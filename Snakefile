## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Snakefile for GLASS-WG pipeline
## Authors: Floris Barthel, Samir Amin
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

import os
import pandas as pd
import itertools

## Import manifest processing functions
from python.glassfunc import dbconfig, locate
from python.PostgreSQLManifestHandler import PostgreSQLManifestHandler
from python.JSONManifestHandler import JSONManifestHandler

## Connect to database
## dbconf = dbconfig("/home/barthf/.odbc.ini", "VerhaakDB")
dbconf = dbconfig(config["db"]["configfile"], config["db"]["configsection"])

#print("Cohort set to ", str(config["cohort"]))
by_cohort = None
if len(str(config["cohort"])) > 0:
    by_cohort = str(config["cohort"]).zfill(2)

## Instantiate manifest
manifest = PostgreSQLManifestHandler(host = dbconf["servername"], port = dbconf["port"], user = dbconf["username"], password = dbconf["password"], database = dbconf["database"],
    source_file_basepath = config["data"]["source_path"], aligned_file_basepath = config["data"]["realn_path"], from_source = config["from_source"], by_cohort = by_cohort)
print(manifest)

## Set working directory based on configuration file
workdir: config["workdir"]

## GDC token file for authentication
KEYFILE = config["gdc_token"]

## Cluster metadata (memory, CPU, etc)
CLUSTER_META = json.load(open(config["cluster_json"]))

## List of scatterlist items to iterate over
## Each Mutect2 run spawns 50 jobs based on this scatterlist

WGS_SCATTERLIST = ["temp_{num}_of_50".format(num=str(j+1).zfill(4)) for j in range(50)]

## Load modules

## We do not want the additional DAG processing if not from source
#if(config["from_source"]):
#    include: "snakemake/download.smk"
#include: "snakemake/align.smk"

#include: "snakemake/mutect2-post.smk"

# include: "snakemake/haplotype-map.smk"
include: "snakemake/fingerprinting.smk"
# include: "snakemake/telseq.smk"
# include: "snakemake/mutect2.smk"
# include: "snakemake/varscan2.smk"
# include: "snakemake/cnvnator.smk"
# include: "snakemake/lumpy.smk"
# include: "snakemake/delly.smk"
# include: "snakemake/manta.smk"
include: "snakemake/cnv.smk"

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Haplotype map creation rule
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule build_haplotype_map:
    input:
        "data/ref/fingerprint.filtered.map"

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Alignment rule
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule align:
    input:
        expand("results/align/bqsr/{aliquot_barcode}.realn.mdup.bqsr.bam", aliquot_barcode = manifest.getSelectedAliquots()),
        expand("results/align/wgsmetrics/{aliquot_barcode}.WgsMetrics.txt", aliquot_barcode = manifest.getSelectedAliquots()),
        expand("results/align/validatebam/{aliquot_barcode}.ValidateSamFile.txt", aliquot_barcode = manifest.getSelectedAliquots()),
        lambda wildcards: ["results/align/fastqc/{sample}/{sample}.{rg}.unaligned_fastqc.html".format(sample = aliquot_barcode, rg = readgroup)
          for aliquot_barcode, readgroups in manifest.getSelectedReadgroupsByAliquot().items()
          for readgroup in readgroups]

rule missingmetrics:
    input:
        expand("results/align/wgsmetrics/{aliquot_barcode}.WgsMetrics.txt", aliquot_barcode = manifest.getSelectedAliquots()),
        expand("results/align/validatebam/{aliquot_barcode}.ValidateSamFile.txt", aliquot_barcode = manifest.getSelectedAliquots())

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Download only rule
## Run snakemake with 'snakemake download_only' to activate
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

#rule download_only:
#   input: expand("{file}", file = ALIQUOT_TO_BAM_PATH.values())

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## QC rule
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule qc:
    input: 
        "results/align/multiqc/multiqc_report.html"

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## SNV rule (Mutect2)
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule mutect2:
    input:
        expand("results/mutect2/vcf2maf/{pair_barcode}.final.maf", pair_barcode = manifest.getSelectedPairs())#,
    	#expand("results/mutect2/final/{pair_barcode}.final.vcf", pair_barcode = manifest.getSelectedPairs())

rule mutect2post:
	input:
		expand("results/mutect2/m2post/{pair_barcode}.normalized.sorted.vcf.gz", pair_barcode = manifest.getSelectedPairs())

rule genotypefreebayes:
    input:
        expand("results/mutect2/freebayes/{aliquot_barcode}.normalized.sorted.vcf.gz", aliquot_barcode = manifest.getSelectedAliquots())

rule massfreebayes:
    input:
        expand("results/mutect2/freebayes/batch{batch}/{aliquot_barcode}.normalized.sorted.vcf.gz", batch = [str(i) for i in range(2,6)], aliquot_barcode = manifest.getSelectedAliquots())

rule genotypevcf2vcf:
    input:
        expand("results/mutect2/genotypes/{aliquot_barcode}.normalized.sorted.vcf.gz", aliquot_barcode = manifest.getSelectedAliquots())

rule finalfreebayes:
    input:
        expand("results/mutect2/batches2db/{aliquot_barcode}.normalized.sorted.tsv", aliquot_barcode = manifest.getSelectedAliquots())

rule preparem2pon:
    input:
        expand("results/mutect2/mergepon/{aliquot_barcode}.pon.vcf", aliquot_barcode = manifest.getPONAliquots())

rule genodb:
    input:
        expand("results/mutect2/geno2db/{aliquot_barcode}.normalized.sorted.tsv", aliquot_barcode = manifest.getSelectedAliquots())

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## PON rule (Mutect2)
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule mutect2pon:
    input:
    	"results/mutect2/pon/pon.vcf"

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## SNV rule (VarScan2)
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule varscan2:
    input:
        expand("results/varscan2/fpfilter/{pair_barcode}.{type}.Somatic.hc.final.vcf", pair_barcode = manifest.getSelectedPairs(), type = ["snp", "indel"])

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## CNV calling pipeline
## Run snakemake with target 'svprepare'
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 



rule cnv:
    input:
        expand("results/cnv/plotcr/{aliquot_barcode}/{aliquot_barcode}.denoised.png", aliquot_barcode = manifest.getSelectedAliquots()),
        expand("results/cnv/plotmodeledsegments/{aliquot_barcode}/{aliquot_barcode}.modeled.png", aliquot_barcode = manifest.getSelectedAliquots()),
        
        #expand("results/cnv/acs_convert/{pair_barcode}.acs.seg", pair_barcode = manifest.getSelectedPairs()),
        #expand("results/cnv/gistic_convert/{pair_barcode}.gistic2.seg", pair_barcode = manifest.getSelectedPairs()),
        
        #expand("results/cnv/absolute/{pair_barcode}/{pair_barcode}.ABSOLUTE_plot.pdf", pair_barcode = manifest.getSelectedPairs()),
        #expand("results/cnv/combinetracks/{pair_barcode}.final.seg", pair_barcode = manifest.getSelectedPairs()),
        #expand("results/cnv/acs_convert/{pair_barcode}/{pair_barcode}.ABSOLUTE_plot.pdf", pair_barcode = manifest.getSelectedPairs())
        #expand("results/cnv/callsegments/{pair_barcode}.called.seg", pair_barcode = manifest.getSelectedPairs()),
        #expand("results/cnv/plotmodeledsegments/{pair_barcode}/{pair_barcode}.modeled.png", pair_barcode = manifest.getSelectedPairs()),
        #expand("results/cnv/plotcr/{aliquot_barcode}/{aliquot_barcode}.denoised.png", aliquot_barcode = manifest.getSelectedAliquots()),

rule titancna:
    input:
        expand("results/cnv/titan/{pair_barcode}/{pair_barcode}.optimalClusters.txt", pair_barcode = manifest.getSelectedPairs()),
        expand("results/cnv/titanfinal/seg/{pair_barcode}.seg.txt", pair_barcode = manifest.getSelectedPairs())

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Call SV using Delly
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule delly:
    input:
        expand("results/delly/filter/{pair_barcode}.prefilt.bcf", pair_barcode = manifest.getSelectedPairs())

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Call SV using LUMPY-SV
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule lumpy:
    input:
        expand("results/lumpy/svtyper/{pair_barcode}.dict.svtyper.vcf", pair_barcode = manifest.getSelectedPairs()),
        #expand("results/lumpy/libstat/{pair_barcode}.libstat.pdf", pair_barcode = manifest.getSelectedPairs()),
        expand("results/lumpy/filter/{pair_barcode}.dict.svtyper.filtered.vcf", pair_barcode = manifest.getSelectedPairs())

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Call SV using Manta
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule manta:
    input:
        expand("results/manta/{pair_barcode}/results/variants/somaticSV.vcf.gz", pair_barcode = manifest.getSelectedPairs())

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Call CNV using Manta
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule cnvnator:
    input:
        expand("results/cnvnator/vcf/{aliquot_barcode}.call.vcf", aliquot_barcode = manifest.getSelectedAliquots())

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Call SVs using all callers
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule svdetect:
    input:
        expand("results/lumpy/svtyper/{pair_barcode}.dict.svtyper.vcf", pair_barcode = manifest.getSelectedPairs()),
        expand("results/lumpy/libstat/{pair_barcode}.libstat.pdf", pair_barcode = manifest.getSelectedPairs()),
        expand("results/delly/call/{pair_barcode}.vcf.gz", pair_barcode = manifest.getSelectedPairs()),
        expand("results/manta/{pair_barcode}/results/variants/somaticSV.vcf.gz", pair_barcode = manifest.getSelectedPairs())

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Estimate TL using telseq
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule telseq:
    input:
        expand("results/telseq/{aliquot_barcode}.telseq.txt", aliquot_barcode = manifest.getSelectedAliquots())

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
## Fingerprinting pipeline
## Check sample and case fingerprints
## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 

rule fingerprint:
   input:
       expand("results/fingerprinting/sample/{aliquot_barcode}.crosscheck_metrics", aliquot_barcode = manifest.getSelectedAliquots()),
       expand("results/fingerprinting/case/{case_barcode}.crosscheck_metrics", case_barcode = manifest.getSelectedCases()),
       "results/fingerprinting/GLASS.crosscheck_metrics",
       

## END ##
