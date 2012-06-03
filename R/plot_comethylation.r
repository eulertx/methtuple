# Peter Hickey
# 01/06/2012
# Plots of within-fragment comethylation

#### TODOs ####
# TODO: Fix lor() to allow aggregateByNIC
# Add all genomic-feature stratified lor-plots
# Implement strand-specificity in plotLorByLag
# Plot lors by number of CpGs/separation
# The construction of genomic-feature GRanges instances, while 99% correct, are are not done to publication-standard. This should be fixed prior to publication of code.

#### Read in command line arguments ####
args <- commandArgs(TRUE)
# The name of the sample of interest
sample.name <- args[1]
# The number of cores to be used for parallel processing
n.cores <- args[2]
# Path to genomic-features.RData object
path.to.gf <- args[3]

#### Load genomic-features.RData, created by running create_genomic_features
load(path.to.df)

#### Load libraries ####
library(stringr)
library(GenomicRanges)
library(plyr)
library(ggplot2)
library(doMC)
library(rtracklayer)
library(BSgenome)
library('BSgenome.Hsapiens.UCSC.hg18')

#### Register the doMC backend ####
registerDoMC(cores = n.cores)

#### Function definitions ####
# Output is a genomic ranges object with start = C in CpG1 and end = C in CpG2
# If chromosomes == 'all' then we use chr1, ..., chr22, chrX and chrY. We don't use chrM because it is a circular chromosome, which breaks subsetByOverlaps()
readWF <- function(sample.name, chromosomes = 'all', pairChoice = 'all'){
  # Construct a list of chromosome names that are to have lag-correlations computed.
  if(chromosomes == 'all'){
    chromosome.list <- list('chr1', 'chr2', 'chr3', 'chr4', 'chr5', 'chr6', 'chr7', 'chr8', 'chr9', 'chr10', 'chr11', 'chr12', 'chr13',
                            'chr14', 'chr15', 'chr16', 'chr17', 'chr18', 'chr19', 'chr20', 'chr21', 'chr22', 'chrX', 'chrY')
    names(chromosome.list) <- chromosome.list
  } else{
    chromosome.list <- list(chromosomes)
    names(chromosome.list) <- chromosomes
  }
  WF.files <- list()
  for(chrom in names(chromosome.list)){
    if(pairChoice == 'all'){
      filename <- str_c(sample.name, '_', chrom, '.wf')
    } else if(pairChoice == 'outermost'){
      filename <- str_c(sample.name, '_', chrom, '_outermost.wf')
    }
    WF.files[[chrom]] <- read.table(filename, sep = '\t', stringsAsFactors = FALSE, header = TRUE)
  }
  WF.df <- rbind.fill(WF.files)
  WF.gr <- GRanges(seqnames = WF.df$chr, ranges = IRanges(start = WF.df$pos1, end = WF.df$pos2), counts = DataFrame(WF.df[, 4:15]))
  names(values(WF.gr)) <- str_sub(names(values(WF.gr)), 8)
  seqlengths(WF.gr)[names(chromosome.list)] <- seqlengths(Hsapiens)[names(chromosome.list)]
  rm(WF.df)
  return(WF.gr)
}

# Compute the log-odds ratio (lor) for a single CpG-pair or aggregate across CpG-pairs and then compute lor
# x is the output of readWF(), strand is which strand is analysed (combined, OT or OB), aggregate is whether to aggregate the counts across multiple CpG-pairs
lor <- function(x, strand = 'combined', aggregateByLag = FALSE, aggregateByNIC = FALSE){
  if(aggregateByLag & aggregateByNIC){
    stop('Only ONE of aggregateByLag or aggregateByNIC can be TRUE')
  }
  x.em <- elementMetadata(x)
  if(aggregateByLag == TRUE){
    agg.df <- data.frame(lag = width(x) - 1,
                         MM = x.em$MM,
                         MU = x.em$MU,
                         UM = x.em$UM,
                         UU = x.em$UU
    )
    agg.counts <- ddply(.data = agg.df, .variables = 'lag', .fun = function(x){colSums(x[, c('MM', 'MU', 'UM', 'UU')])}, .parallel = TRUE)                     
    MM <- agg.counts$MM
    MU <- agg.counts$MU
    UM <- agg.counts$UM
    UU <- agg.counts$UU
  } else{
    if(strand == 'combined'){
      MM <- x.em$MM
      MU <- x.em$MU
      UM <- x.em$UM
      UU <- x.em$UU
    }else if(strand == 'OT'){
      MM <- x.em$MM_OT
      MU <- x.em$MU_OT
      UM <- x.em$UM_OT
      UU <- x.em$UU_OT
    }else if(strand == 'OB'){
      MM <- x.em$MM_OB
      MU <- x.em$MU_OB
      UM <- x.em$UM_OB
      UU <- x.em$UU_OB
    }
  }
  # Continuity correct the counts
    MM <- MM + 0.5
    MU <- MU + 0.5
    UM <- UM + 0.5
    UU <- UU + 0.5
  # Compute lor and its asymptotic standard error (ASE)
  lor <- ifelse(MM == 0.5 & MU == 0.5 & UM == 0.5 & UU == 0.5, NA, log(MM * UU / (MU * UM)))
  ASE <- ifelse(MM == 0.5 & MU == 0.5 & UM == 0.5 & UU == 0.5, NA, sqrt(1/MM + 1/MU + 1/UM + 1/MU))
  if(aggregate == TRUE){
    return.df <- data.frame(lag = agg.counts$lag, lor = lor, ASE = ASE)
  } else{
    return.df <- data.frame(lor = lor, ASE = ASE)
  }
  return(return.df)
}

# Plot boxplot of LORs as a function of a intra-pair separation from the WF.gr instance
plotLorBoxplotByLag <- function(x, ...){
  df <- data.frame(lag = width(x) - 1, # Minus one so the lag-values are on the same scale as for the COAM plots
                   lor = elementMetadata(x)$lor,
                   cov = elementMetadata(x)$cov
                   )
  boxplot(lor ~ lag, data = df, xlab = 'lag', ylab = 'lor', ...)
}

# Plot aggregated LORs computed from WF_outermost.gr
plotAggregatedLorByLag <- function(x, title, error.bars = TRUE, ...){
  if(error.bars == TRUE){
    error.bars <- aes(ymax = lor + 2*ASE, ymin = lor - 2*ASE)
    ggplot(data = x, aes(x = lag, y = lor)) + geom_point() + opts(title = title) + scale_x_continuous('Distance between CpGs') + scale_y_continuous(limits = c(0, 7), 'log-odds ratio') + geom_errorbar(error.bars)
  } else{
    ggplot(data = x, aes(x = lag, y = lor)) + geom_point() + opts(title = title) + scale_x_continuous('Distance between CpGs') + scale_y_continuous(limits = c(0, 7), 'log-odds ratio') 
  }
}

# 'genome' is a BSgenome object, 'x' is a GRanges object, e.g. WF_outermost.gr
countInterveningCpGs <- function(x, genome){
  CpG.seq <- getSeq(genome, names = x)
  n.intervening.CpGs <- vcountPattern(pattern = "CG", subject = CpG.seq) - 1 # Minus one to exlude the CpG that corresponds to CpG_1 of the CpG-pair
}

#### Read in the data ####
WF.gr <- readWF(sample.name, chromosomes = 'all', pairChoice = 'all')
WF_outermost.gr <- readWF(sample.name, chromosomes = 'all', pairChoice = 'outermost')

#### Compute log-odds ratios for each CpG-pair ####
elementMetadata(WF.gr)$lor <- lor(WF.gr, strand = 'combined', aggregate = FALSE)$lor
elementMetadata(WF.gr)$lor_OT <- lor(WF.gr, strand = 'OT', aggregate = FALSE)$lor
elementMetadata(WF.gr)$lor_OB <- lor(WF.gr, strand = 'OB', aggregate = FALSE)$lor

#### Compute coverage of each CpG-pair ####
elementMetadata(WF.gr)$cov <- elementMetadata(WF.gr)$MM + elementMetadata(WF.gr)$MU + elementMetadata(WF.gr)$UM + elementMetadata(WF.gr)$UU
elementMetadata(WF.gr)$cov_OT <- elementMetadata(WF.gr)$MM_OT + elementMetadata(WF.gr)$MU_OT + elementMetadata(WF.gr)$UM_OT + elementMetadata(WF.gr)$UU_OT
elementMetadata(WF.gr)$cov_OB <- elementMetadata(WF.gr)$MM_OB + elementMetadata(WF.gr)$MU_OB + elementMetadata(WF.gr)$UM_OB + elementMetadata(WF.gr)$UU_OB

#### See how coverage affects boxplots ####
pdf(file = str_c('plots/', sample.name, '_lor_boxplots.pdf'), height = 14, width = 14)
par(mfrow = c(2,2))
min.cov <- 1
plotLorByLag(subset(WF.gr, elementMetadata(WF.gr)$cov >= min.cov), main = str_c(sample.name, ': min.cov = ', min.cov), ylim = c(-6, 6))
min.cov <- quantile(elementMetadata(WF.gr)$cov, 0.5)
plotLorByLag(subset(WF.gr, elementMetadata(WF.gr)$cov >= min.cov), main = str_c(sample.name, ': min.cov = ', min.cov, '\n(upper 50% of coverage distribution)'), ylim = c(-6, 6))
min.cov <- quantile(elementMetadata(WF.gr)$cov, 0.75)
plotLorByLag(subset(WF.gr, elementMetadata(WF.gr)$cov >= min.cov), main = str_c(sample.name, ': min.cov = ', min.cov, '\n(upper 25% of coverage distribution)'), ylim = c(-6, 6))
min.cov <- quantile(elementMetadata(WF.gr)$cov, 0.9)
plotLorByLag(subset(WF.gr, elementMetadata(WF.gr)$cov >= min.cov), main = str_c(sample.name, ': min.cov = ', min.cov, '\n(upper 10% of coverage distribution)'), ylim = c(-6, 6))
dev.off()

#### 

#### Aggregate-by-number-of-intervening-CpGs ####
elementMetadata(WF_outermost.gr)$NIC <- countInterveningCpGs(WF_outermost.gr, Hsapiens)

#### Plot aggregated-by-lag log-odds ratios stratified by various genomic features ####
# No stratification
tmp.gr <- WF_outermost.gr
tmp.lor <- lor(x = tmp.gr, aggregate = TRUE)
plotAggregatedLorByLag(tmp.lor, title = str_c('Within-fragment comethylation\n', sample.name), error.bars = FALSE)
ggsave(str_c('plots/', sample.name, '_aggregated_lor_genome_wide.pdf'))
plotAggregatedLorByLag(tmp.lor, title = str_c('Within-fragment comethylation\n', sample.name), error.bars = TRUE)
ggsave(str_c('plots/', sample.name, '_aggregated_lor_genome_wide_se.pdf'))

# In CGI
tmp.gr <- subsetByOverlaps(WF_outermost.gr, CGI, type = 'within')
tmp.lor <- lor(x = tmp.gr, aggregate = TRUE)
plotAggregatedLorByLag(tmp.lor, title = str_c('Within-fragment comethylation\n', sample.name, ': CpGs in CGIs'), error.bars = FALSE)
ggsave(str_c('plots/', sample.name, '_aggregated_lor_in_CGI.pdf'))
plotAggregatedLorByLag(tmp.lor, title = str_c('Within-fragment comethylation\n', sample.name, ': CpGs in CGIs'), error.bars = TRUE)
ggsave(str_c('plots/', sample.name, '_aggregated_lor_in_CGI_se.pdf'))

# Not in CGI
tmp.gr <- subsetByOverlaps(WF_outermost.gr, outside.CGI, type = 'within')
tmp.lor <- lor(x = tmp.gr, aggregate = TRUE)
plotAggregatedLorByLag(tmp.lor, title = str_c('Within-fragment comethylation\n', sample.name, ': CpGs not in CGIs'), error.bars = FALSE)
ggsave(str_c('plots/', sample.name, '_aggregated_lor_out_CGI.pdf'))
plotAggregatedLorByLag(tmp.lor, title = str_c('Within-fragment comethylation\n', sample.name, ': CpGs not in CGIs'), error.bars = TRUE)
ggsave(str_c('plots/', sample.name, '_aggregated_lor_out_CGI_se.pdf'))

# knownGene aka UCSC genes
tmp.gr <- subsetByOverlaps(WF_outermost.gr, knownGene, type = 'within')
tmp.lor <- lor(x = tmp.gr, aggregate = TRUE)
plotAggregatedLorByLag(tmp.lor, title = str_c('Within-fragment comethylation\n', sample.name, ': CpGs in knownGenes'), error.bars = FALSE)
ggsave(str_c('plots/', sample.name, '_aggregated_lor_in_knownGene.pdf'))
plotAggregatedLorByLag(tmp.lor, title = str_c('Within-fragment comethylation\n', sample.name, ': CpGs in knownGenes'), error.bars = TRUE)
ggsave(str_c('plots/', sample.name, '_aggregated_lor_in_knownGene_se.pdf'))

# Not in knownGene
tmp.gr <- subsetByOverlaps(WF_outermost.gr, outside.knownGene, type = 'within')
tmp.lor <- lor(x = tmp.gr, aggregate = TRUE)
plotAggregatedLorByLag(tmp.lor, title = str_c('Within-fragment comethylation\n', sample.name, ': CpGs not in knownGenes'), error.bars = FALSE)
ggsave(str_c('plots/', sample.name, '_aggregated_lor_out_knownGene.pdf'))
plotAggregatedLorByLag(tmp.lor, title = str_c('Within-fragment comethylation\n', sample.name, ': CpGs not in knownGenes'), error.bars = TRUE)
ggsave(str_c('plots/', sample.name, '_aggregated_lor_out_knownGene_se.pdf'))

# Continue with all the other genomic-features