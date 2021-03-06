RDIR = "../R"
FILES = "../lib"
FILESX = "../libx"
PGX.DIR = "../data"
FILES
source(file.path(RDIR,"pgx-include.R"))

pgx.files <- dir(".", pattern=".pgx")
##pgx.files <- grep("X.pgx$",pgx.files,invert=TRUE,value=TRUE)
##pgx.files <- dir("../data.BAK/", pattern=".pgx",full.names=TRUE)

pgx.files
pgx.file = pgx.files[1]
pgx.file = pgx.files[9]
pgx.file

for(pgx.file in pgx.files) {
    
    cat("*********** updating",pgx.file,"**********\n")    
    load(pgx.file, verbose=1)
    object.size(ngs)/1e6

    names(ngs)
    names(ngs$connectivity)
    names(ngs$drugs)
    
    if(0 && "connectivity" %in% names(ngs)) {
        cat("already done. skipping...\n")
        next()
    }
    
    ##extra <- c("meta.go","deconv","infer","drugs","wordcloud")
    extra <- c("drugs","connectivity")
    extra <- c("drugs-combo")
    extra <- c("connectivity")
    ##ngs$connectivity <- NULL
    ##ngs$drugs <- NULL
    sigdb = "../libx/sigdb-gtex.h5"
    sigdb = c("../libx/sigdb-lincs.h5","../libx/sigdb-creeds.h5","../libx/sigdb-drugsx.h5")
    all.db <- dir("../libx","sigdb.*h5$")
    db1 <- setdiff(all.db, names(ngs$connectivity))
    db1
    if(length(db1)==0) next()    
    sigdb = paste0("../libx/",db1)

    sigdb = c("../libx/sigdb-lincs-cp.h5","../libx/sigdb-lincs-gt.h5")
    
    ngs <- compute.extra(ngs, extra, lib.dir=FILES, sigdb=sigdb )     

    ngs$connectivity[["sigdb-lincs.h5"]] <- NULL
    names(ngs$connectivity)
    
    ##------------------ save new object -------------------
    names(ngs)
    ngs.save(ngs, file=pgx.file)    

    
}










