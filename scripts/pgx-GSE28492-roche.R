rm(list=ls())
library(knitr)
library(limma)
library(edgeR)
library(RColorBrewer)
library(gplots)
library(matrixTests)
library(kableExtra)
library(knitr)

source("../R/gx-heatmap.r")
source("../R/gx-limma.r")
source("../R/gx-util.r")
source("../R/ngs-cook.r")
source("../R/ngs-fit.r")
source("../R/gset-fisher.r")
source("../R/gset-gsea.r")
source("../R/gset-meta.r")
source("../R/pgx-graph.R")
source("../R/pgx-functions.R")

FILES="../lib/"
RDIR="../R/"

PROCESS.DATA=1
DIFF.EXPRESSION=1
PROCESS.DATA=1
DIFF.EXPRESSION=1

if(0) {
    SMALL=4000
    FAST=TRUE
    EXT="4k"
}

##rda.file="../files/rieckmann2017-immprot.pgx"
rda.file="../pgx/GSE28492-roche-miRmRNA.pgx"
if(SMALL>0) rda.file = sub(".pgx$",paste0("-",EXT,".pgx"),rda.file)
rda.file

##load(file=rda.file, verbose=1)
ngs <- list()  ## empty object
ngs$name = gsub("^.*pgx/|[.]pgx$","",rda.file)
ngs$date = date()
ngs$datatype = "mRNA + miRNA (microarray)"
ngs$description = "GSE28492 combined mRNA+microRNA expression data set from the paper 'Expression profiling of human immune cell subsets identifies miRNA-mRNA regulatory relationships correlated with cell type specific expression' (Allantaz et al., PLoS One 2012). Blood consists of different cell populations with distinct functions and correspondingly, distinct gene expression profiles. Global mRNA expression profiling was performed across a panel of nine human immune cell subsets (neutrophils, eosinophils, monocytes, B cells, NK cells, CD4 T cells, CD8 T cells, mDCs and pDCs) to identify cell-type specific microRNA expression. mRNA expression profiling was performed on the same samples, to determine if miRNAs specific to certain cell types down-regulated expression levels of their target genes."

## READ/PARSE DATA
if(PROCESS.DATA) {

    ## Version info: R 3.2.3, Biobase 2.30.0, GEOquery 2.40.0, limma 3.26.8
    ## R scripts generated  Sun Sep 23 19:43:35 EDT 2018
    library(Biobase)
    library(GEOquery)

    ## load series and platform data from GEO
    geo <- getGEO("GSE28492", GSEMatrix =TRUE, AnnotGPL=TRUE)
    length(geo)
    attr(geo, "names")

    ##----------------------------------------------------------------------
    ## Parse mRNA gene expression HGU133plus2
    ##----------------------------------------------------------------------
    parse.expression <- function() {
        idx <- grep("GPL570", attr(geo, "names"))
        gset <- geo[[idx]]
        pdata = pData(gset)
        cell.type = pdata[,"cell type:ch1"]
        cell.type = gsub("[ +-]","",cell.type)
        table(cell.type)
        cell.type = sub("^Bcells$","CD19Bcells",cell.type)
        cell.type = sub("^Monocytes$","CD14monocytes",cell.type)

        ##repl = gsub(".*rep| mRNA.*$","",pdata$title)
        repl = paste0("rep",gsub(".*rep| mRNA.*$","",pdata$title))
        src  = gsub(".*\\(|\\)$","",pdata$title)
        donor = sub(".*donor pool ","donor",pdata$source_name_ch1)
        sampleTable = data.frame( cell.type = cell.type,
                                 title = pdata$title,
                                 donor = donor,
                                 repl=repl, batch=src)
        rownames(sampleTable) = rownames(pdata)

        ## conform samples
        X = exprs(gset)
        X = X[which(rowMeans(is.na(X)) == 0), ]
        X = X[order(-apply(X,1,sd)),]
        sum(is.na(X))
        dim(X)

        samples = intersect( rownames(sampleTable), colnames(X))
        X = X[,samples]
        sampleTable = sampleTable[samples,]

        ## convert affymetrix ID to GENE symbol
        ##source("https://bioconductor.org/biocLite.R")
        ##biocLite("hgu133plus2.db")
        library(hgu133plus2.db)
        affx.symbol = sapply(as.list(hgu133plus2SYMBOL),"[[",1)
        symbol = affx.symbol[rownames(X)]
                    head(symbol)
        rownames(X) = symbol
        X = X[which(!duplicated(symbol) & !is.na(symbol)),]
        dim(X)

        ## gene annotation
        require(org.Hs.eg.db)
        GENE.TITLE = unlist(as.list(org.Hs.egGENENAME))
        gene.symbol = unlist(as.list(org.Hs.egSYMBOL))
        names(GENE.TITLE) = gene.symbol
        head(GENE.TITLE)
        gene_title <- GENE.TITLE[rownames(X)]
        genes = data.frame( gene_name=rownames(X), gene_title=gene_title)
        ##genes = apply(genes,2,as.character)
        head(genes)

        ## give tagged rownames
        ##rownames(X) = paste0("tag",1:nrow(X),":",genes$gene_name)  ## add one gene to tags
        rownames(genes) = rownames(X)
        list(X=X, genes=genes, sampleTable=sampleTable)
    }
    
    ##----------------------------------------------------------------------
    ## Parse microRNA expression
    ##----------------------------------------------------------------------
    parse.microRNA <- function() {
        idx <- grep("GPL8786", attr(geo, "names"))
        gset <- geo[[idx]]
        pdata = pData(gset)
        head(pdata)
        cell.type = pdata[,"cell type:ch1"]
        cell.type = gsub("[ +-]","",cell.type)
        table(cell.type)
        cell.type = sub("^Bcells$","CD19Bcells",cell.type)
        cell.type = sub("^Monocytes$","CD14monocytes",cell.type)

        repl = paste0("rep",gsub(".*rep| miRNA.*$","",pdata$title))
        src  = gsub(".*\\(|\\)$","",pdata$title)
        donor = sub(".*donor pool ","donor",pdata$source_name_ch1)
        sampleTable = data.frame( cell.type = cell.type,
                                 title = pdata$title,
                                 donor = donor,
                                 repl=repl, batch=src)
        rownames(sampleTable) = rownames(pdata)

        ## get miRNA expression
        X = exprs(gset)
        X = X[which(rowMeans(is.na(X)) == 0), ]
        X = X[order(-apply(X,1,sd)),]
        sum(is.na(X))
        dim(X)
        X = X[grep("hsa",rownames(X)),] ## get only human miRNA
        dim(X)

        ## conform samples
        samples = intersect( rownames(sampleTable), colnames(X))
        X = X[,samples]
        sampleTable = sampleTable[samples,]

        ## gene annotation
        require(org.Hs.eg.db)
        gene_title <- paste("microRNA", rownames(X))
        
        alt.name <- sub("HSA-MIR-","MIR",toupper(rownames(X)))
        alt.name <- sub("HSA-LET-","MIRLET",alt.name)
        alt.name <- gsub("_ST|-STAR_ST","",alt.name)
        alt.name <- gsub("-3P|-5P","",alt.name)
        sum(duplicated(alt.name))

        jj <- which(!duplicated(alt.name))
        genes = data.frame( gene_name=alt.name,
                           gene_title=gene_title)[jj,]
        rownames(genes) = alt.name[jj]
        X <- X[jj,]
        rownames(X) = alt.name[jj]
        
        list(X=X, genes=genes, sampleTable=sampleTable)
    }

    res1 = parse.expression()
    res2 = parse.microRNA()
    dim(res1$X)
    dim(res2$X)

    donor1 = paste(res1$sampleTable$cell.type, res1$sampleTable$donor,sep="_")
    donor2 = paste(res2$sampleTable$cell.type, res2$sampleTable$donor,sep="_")
    common.donor = intersect(donor1, donor2)
    
    ## scale to same median
    j1 = match( common.donor, donor1)
    j2 = match( common.donor, donor2)
    X1 = res1$X[,j1]
    X2 = res2$X[,j2]
    par(mfrow=c(2,2));gx.hist(X1[,1:10]);gx.hist(X2[,1:10])
    X2 = (X2 - median(X2)) + median(X1)
    gx.hist(X1[,1:10]);gx.hist(X2[,1:10])
    X = rbind(X1, X2)

    s1 = rownames(res1$sampleTable)[j1]
    s2 = rownames(res2$sampleTable)[j2]
    sampleTable = res1$sampleTable[j1,]
    ##sampleTable = res2$sampleTable[j2,]
    genes = rbind( res1$genes, res2$genes )
    colnames(X) = rownames(sampleTable) = paste(s1,s2,sep="_")
    sampleTable$title <- NULL

    if(0) {

        gx.hist( X)
        cc0 = sampleTable[colnames(X),c("batch","cell.type")]
        labCol = paste(colnames(X), "-", sampleTable$cell.type)
        gx.heatmap(X, nmax=2000, col.annot=cc0, mar=c(30,10),
                   scale="rowcenter", cexCol=1, labCol=labCol)
        gx.heatmap(X, nmax=80, col.annot=cc0, mar=c(30,10),
                   scale="rowcenter", cexCol=1, labCol=labCol)

        require(sva)
        require(limma)
        design = model.matrix( ~ sampleTable$cell.type )
        X2 = ComBat(X, batch=as.character(sampleTable$batch))
        X2 = removeBatchEffect(X, batch=as.character(sampleTable$batch),
                               design=design)
        X2 = normalizeQuantiles(X2)
        gx.heatmap(X2, nmax=1000, col.annot=cc0, mar=c(30,10),
                   cexCol=1, labCol=labCol, scale="rowcenter")
        X2 = X2 - rowMeans(X2)
        gx.heatmap(X2, nmax=80, col.annot=cc0, mar=c(30,10),
                   cexCol=1, labCol=labCol, scale="none")
    }

    ## no more batch for mRNA*miRNA matched samples
    ##sampleTable$batch <- NULL

    if(0) {
        require(sva)
        require(limma)
        design = model.matrix( ~ sampleTable$cell.type )
        ##X2 = ComBat(X, batch=as.character(sampleTable$batch))
        bX = removeBatchEffect(X, batch=as.character(sampleTable$batch),
                               design=design)
        ##bX = normalizeQuantiles(bX)
    }

    ## treat RMA as counts
    ##counts = round(2**bX)
    counts = (2**X)
    sum(is.nan(as.matrix(counts)))
    min(counts)
    ##counts[is.nan(counts)] = 0
    ##counts = round(counts / 1e6)  ## too big for R integers, divide by 1M

    ## sample annotation
    ##short.names <- paste(sampleTable$cell.type,sampleTable$batch,sampleTable$repl,sep="_")
    short.names <- paste(sampleTable$cell.type,sampleTable$repl,sep="_")
    short.names <- sub("Roche_","R",short.names)
    short.names <- sub("HUG_","H",short.names)
    short.names <- gsub("[ ]","",short.names)
    short.names
    colnames(counts) <- short.names
    rownames(sampleTable) <- short.names
    sampleTable$group = sampleTable$cell.type
    table(sampleTable$group)

    ##-------------------------------------------------------------------
    ## Now create an DGEList object  (see tximport Vignette)
    ##-------------------------------------------------------------------
    library(limma)
    library(edgeR)
    if(is.null(sampleTable$group)) stop("samples need group")
    table(sampleTable$group)
    ngs$counts <- round(counts)
    ngs$samples <- sampleTable
    ngs$genes = genes
    ##lib.size <- colSums(data$counts / 1e6)  ## get original summed intensity as lib.size
    ngs$samples$batch <- NULL
    ##ngs$samples$batch <- as.integer(lib.size2)
    
    ## tagged rownames
    row.id = paste0("tag",1:nrow(ngs$genes),":",ngs$genes[,"gene_name"])
    rownames(ngs$genes) = rownames(ngs$counts) = row.id
    names(ngs)

    ##-------------------------------------------------------------------
    ## sample QC filtering
    ##-------------------------------------------------------------------
    ##

    ##-------------------------------------------------------------------
    ## collapse multiple row for genes by summing up counts
    ##-------------------------------------------------------------------
    sum(duplicated(ngs$genes$gene_name))
    x1 = apply(ngs$counts, 2, function(x) tapply(x, ngs$genes$gene_name, sum))
    ngs$genes = ngs$genes[match(rownames(x1),ngs$genes$gene_name),]
    ngs$counts = x1
    rownames(ngs$genes) = rownames(ngs$counts) = rownames(x1)
    remove(x1)

    ##-------------------------------------------------------------------
    ## gene filtering
    ##-------------------------------------------------------------------
    ##keep <- rep(TRUE,nrow(ngs$counts))
    ##keep <- filterByExpr(ngs)  ## default edgeR filter
    keep <- (rowSums(edgeR::cpm(ngs$counts, log=TRUE) > 1) >=3)
    table(keep)
    ngs$counts <- ngs$counts[keep,]
    ngs$genes  <- ngs$genes[keep,]

    if(SMALL>0) {
        cat("shrinking data matrices: n=",SMALL,"\n")
        j0 = grep("hsa-miR",rownames(ngs$counts))
        j1 = grep("hsa-miR",rownames(ngs$counts),invert=TRUE)
        logcpm = edgeR::cpm(ngs$counts,log=TRUE)
        j1 = j1[order(-apply(logcpm[j1,],1,sd))]
        j1 = head(j1, SMALL)  ## how many genes?
        jj = c(j0,j1)   ## all miRNA!!
        head(jj)
        ngs$counts <- ngs$counts[jj,]
        ngs$genes  <- ngs$genes[jj,]
        dim(ngs$counts)
    }

    save(ngs, file=rda.file)
}


if(DIFF.EXPRESSION) {
    load(file=rda.file, verbose=1)

    levels = levels(ngs$samples$group)
    levels

    ## contr.matrix <- makeContrasts(
    ##     CD4Tcells_vs_CD14monocytes = CD4Tcells - CD14monocytes,
    ##     CD8Tcells_vs_CD14monocytes = CD8Tcells - CD14monocytes,
    ##     mDCs_vs_CD14monocytes = mDCs - CD14monocytes,
    ##     CD19Bcells_vs_CD14monocytes = CD19Bcells - CD14monocytes,
    ##     Neutrophils_vs_CD14monocytes = Neutrophils - CD14monocytes,
    ##     levels = levels)

    contr.matrix <- makeFullContrasts(levels)
    dim(contr.matrix)
    head(contr.matrix)

    ##contr.matrix = contr.matrix[,1:3]
    source("../R/pgx-testgenes.R")

    source("../R/pgx-testgenesets.R")

    source("../R/pgx-extra.R")

}

cat("Finished! Writing final object to file: ",rda.file,"\n")
save(ngs, file=rda.file)


