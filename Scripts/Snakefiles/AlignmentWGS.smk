### Snakefile for mapping of whole-genome sequencing reads from LHISI project

HOME_DIR = "/mnt/data/dayhoff/home/scratch/groups/mikheyev/LHISI"
READ_DIR = HOME_DIR + "/Reads/WGS"
ALN_DIR = HOME_DIR + "/Alignments/WGS"
REF_DIR = HOME_DIR + "/References"
OUT_DIR = HOME_DIR + "/Analysis/AnalysingWGSCoverage"
SOFT_DIR = "/mnt/data/dayhoff/home/u6905905/"

### All libraries were sequenced twice, so each sample has L001 and L002 files
### All sequencing was paired end, so each library has R1 and R2 files
### This is four files per sample

### Get sample names from list file
### Expand into results, which for this case is the completed bam index files
samples = [line.strip() for line in open(SOFT_DIR + "/Daus_WGS_Paper/wgs_sample_list.txt").readlines()]
results_pattern = OUT_DIR + "/{sample}.regions.bed.gz"
results = expand(results_pattern,sample=samples)

rule all:
	input:
		results

### Combine the L001 and L002 reads into one temp file
rule cat:
	input:
		r1_1= READ_DIR + "/{sample}_L001_R1.fastq.gz",
		r1_2= READ_DIR + "/{sample}_L002_R1.fastq.gz",
		r2_1= READ_DIR + "/{sample}_L001_R2.fastq.gz",
		r2_2= READ_DIR + "/{sample}_L002_R2.fastq.gz"
	output:
		r1= READ_DIR + "/temp_{sample}_R1.fastq.gz",
		r2= READ_DIR + "/temp_{sample}_R2.fastq.gz"
	shell:
		"""
		cat {input.r1_1} {input.r1_2} > {output.r1}
		cat {input.r2_1} {input.r2_2} > {output.r2}
		"""

### Map the files to the reference, then sort. Although this is a PCR-free
### protocol, after aligning and observing I did see something obvious
### duplicates. So, we will remove them


rule map:
	input:
		ref=REF_DIR + "/LHISI_Scaffold_Assembly.fasta",
		r1=READ_DIR + "/temp_{sample}_R1.fastq.gz",
		r2=READ_DIR + "/temp_{sample}_R2.fastq.gz"
	output:
		ALN_DIR + "/{sample}.bam"
	params:
		aln = ALN_DIR
	threads: 10
	shell:
		"""
		bwa mem -t {threads} -R "@RG\\tID:{wildcards.sample}\\tSM:{wildcards.sample}\\tLB:NEXTFLEX\\tPL:ILLUMINA" \
		{input.ref} {input.r1} {input.r2} |
		samtools fixmate -m -r -u - - | \
		samtools sort -u -@ {threads} -T {params.aln}/{wildcards.sample}_1 - | \
		samtools markdup -@ {threads} -T {params.aln}/{wildcards.sample}_2 --reference {input.ref} -r -f {params.aln}/{wildcards.sample}_dupstats.txt - - | \
		samtools view -bh >  {output}
		"""

### Index the bam files
rule index:
	input:
		ALN_DIR + "/{sample}.bam"
	output:
		ALN_DIR + "/{sample}.bam.bai"
	threads: 10
	shell:
		"""
		samtools index -@ {threads} {input}
		"""

### Remove the temp files
rule remove:
	input:
		index=ALN_DIR + "/{sample}.bam.bai",
		r1=READ_DIR + "/temp_{sample}_R1.fastq.gz",
		r2=READ_DIR + "/temp_{sample}_R2.fastq.gz"
	shell:
		"""
		rm {input.r1} {input.r2}
		"""

### Calculate depths
rule mosdepth:
	input:
		bai=ALN_DIR + "/{sample}.bam.bai",
		bam=ALN_DIR + "/{sample}.bam"
	output:results_pattern
	threads: 10
	params:
		out=OUT_DIR
	shell:
		"""
		mosdepth \
		--threads {threads} \
		--by 100000 \
		--no-per-base \
		--mapq 30 \
		{params.out}/{wildcards.sample} \
		{input.bam}
		"""
