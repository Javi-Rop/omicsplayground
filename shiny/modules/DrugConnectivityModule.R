DrugConnectivityInputs <- function(id) {
    ns <- NS(id)  ## namespace
    tagList(
        uiOutput(ns("description")),
        uiOutput(ns("inputsUI"))
    )
}

DrugConnectivityUI <- function(id) {
    ns <- NS(id)  ## namespace
    fillCol(
        flex = c(1),
        height = 780,
        tabsetPanel(
            id = ns("tabs"),
            tabPanel("Drug CMap",uiOutput(ns("DSEA_analysis_UI")))
            ## tabPanel("Fire plot (dev)",uiOutput(ns("fireplot_UI")))            
        )
    )
}

DrugConnectivityModule <- function(input, output, session, env)
{
    ns <- session$ns ## NAMESPACE
    inputData <- env[["load"]][["inputData"]]
    fullH = 750
    rowH = 660  ## row height of panel
    tabH = 200  ## row height of panel
    tabH = '70vh'  ## row height of panel    
    description = "<b>Drug Connectivity Analysis</b>. <br> Perform drug connectivity analysis
to see if certain drug activity or drug sensitivity signatures matches your experimental signatures. Matching drug signatures to your experiments may elicudate biological functions through mechanism-of-action (MOA) and known drug molecular targets. "
    output$description <- renderUI(HTML(description))
    
    dr_infotext = paste("<b>This module performs drug enrichment analysis</b> to see if certain drug activity or drug sensitivity signatures matches your experimental signatures. Matching drug signatures to your experiments may elicudate biological functions through mechanism-of-action (MOA) and known drug molecular targets.

<br><br> In the <a href='https://portals.broadinstitute.org/cmap/'>Drug Connectivity Map</a> panel, you can correlate your signature with more than 5000 known drug profiles from the L1000 database. An activation-heatmap compares drug activation profiles across multiple contrasts. This facilitates to quickly see and detect the similarities between contrasts for certain drugs.

<br><br><br><br>
<center><iframe width='500' height='333' src='https://www.youtube.com/embed/watch?v=qCNcWRKj03w&list=PLxQDY_RmvM2JYPjdJnyLUpOStnXkWTSQ-&index=6' frameborder='0' allow='accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture' allowfullscreen></iframe></center>
")

    
    ##================================================================================
    ##========================= INPUTS UI ============================================
    ##================================================================================

    output$inputsUI <- renderUI({
        ui <- tagList(
            tipify( actionLink(ns("dr_info"), "Youtube", icon = icon("youtube") ),
                   "Show more information about this module."),
            hr(), br(),             
            tipify( selectInput(ns("dr_contrast"),"Contrast:", choices=NULL),
                   "Select the contrast corresponding to the comparison of interest.",
                   placement="top"),
            tipify( selectInput(ns('dsea_method'),"Analysis type:", choices = ""),
                   "Select type of drug enrichment analysis: activity or sensitivity (if available).",
                   placement="top"),
                tipify( actionLink(ns("dr_options"), "Options", icon=icon("cog", lib = "glyphicon")),
                   "Show/hide advanced options", placement="top"),
            br(),
            conditionalPanel(
                "input.dr_options % 2 == 1", ns=ns,
                tagList(
                    tipify(checkboxInput(ns('dr_normalize'),'normalize activation matrix',TRUE),
                           "Click to fine-tune the coloring of an activation matrices.")
                )
            )
        )
        ui
    })
    outputOptions(output, "inputsUI", suspendWhenHidden=FALSE) ## important!!!

    observe({
        ngs <- inputData()
        req(ngs)
        ct <- names(ngs$drugs)
        updateSelectInput(session, "dsea_method", choices=ct)
    })
    
    ##================================================================================
    ##======================= OBSERVE FUNCTIONS ======================================
    ##================================================================================
    
    observeEvent( input$dr_info, {
        showModal(modalDialog(
            title = HTML("<strong>Drug Connectivity Analysis Module</strong>"),
            HTML(dr_infotext),
            easyClose = TRUE, size="l" ))
    })

    observe({
        ngs <- inputData()
        req(ngs)
        ct <- colnames(ngs$model.parameters$contr.matrix)
        ##ct <- c(ct,"<sd>")
        updateSelectInput(session, "dr_contrast", choices=ct )
    })
    
    ##================================================================================
    ## Drug signature enrichment analysis L1000
    ##================================================================================

    getDseaTable <- reactive({
        ngs <- inputData()
        alertDataLoaded(session,ngs)
        req(ngs)        
        req(input$dr_contrast, input$dsea_method)

        comparison=1
        names(ngs$gx.meta$meta)
        comparison = input$dr_contrast
        if(is.null(comparison)) return(NULL)
        
        names(ngs$drugs)
        dmethod = "activity/L1000"
        dmethod <- input$dsea_method
        if(is.null(dmethod)) return(NULL)
        
        fc <- ngs$gx.meta$meta[[comparison]]$meta.fx
        names(fc) <- rownames(ngs$gx.meta$meta[[1]])

        nes <- round(ngs$drugs[[dmethod]]$X[,comparison],4)
        pv  <- round(ngs$drugs[[dmethod]]$P[,comparison],4)
        qv  <- round(ngs$drugs[[dmethod]]$Q[,comparison],4)
        drug <- rownames(ngs$drugs[[dmethod]]$X)
        stats <- ngs$drugs[[dmethod]]$stats
        annot <- ngs$drugs[[dmethod]]$annot
        nes[is.na(nes)] <- 0
        qv[is.na(qv)] <- 1
        pv[is.na(pv)] <- 1
        
        ## SHOULD MAYBE BE DONE IN PREPROCESSING???
        if(is.null(annot)) {
            annot <- read.csv(file.path(FILES,"L1000_repurposing_drugs.txt"),
                              sep="\t", comment.char="#")
        }
        
        jj <- match( toupper(drug), toupper(rownames(annot)) )
        annot <- annot[jj,c("moa","target")]        
        res <- data.frame( drug=drug, NES=nes, pval=pv, padj=qv, annot)
        res <- res[order(-abs(res$NES)),]
        
        return(res)
    })


    dsea_enplots.RENDER %<a-% reactive({

        ngs <- inputData()
        if(is.null(ngs$drugs)) return(NULL)
        shiny::validate(need("drugs" %in% names(ngs), "no 'drugs' in object."))        
        req(input$dr_contrast, input$dsea_method)

        comparison=1
        comparison = input$dr_contrast
        if(is.null(comparison)) return(NULL)

        res <- getDseaTable()

        dmethod="mono"
        dmethod="combo"
        dmethod <- input$dsea_method

        ## rank vector for enrichment plots
        rnk <- ngs$drugs[[dmethod]]$stats[,comparison]
        dctype <- sub("_.*$","",names(rnk))
        ##table(rownames(res) %in% dctype)
        ##table(sapply(rownames(res), function(g) sum(grepl(g,names(rnk),fixed=TRUE))))
        
        ## ENPLOT TYPE
        itop <- c( head(order(-res$NES),10), tail(order(-res$NES),10))
        par(oma=c(0,1,0,0))
        par(mfrow=c(4,5), mar=c(1,1.5,1.8,1))
        i=1
        for(i in itop) {
            dx <- rownames(res)[i]
            dx
            gmtdx <- grep(dx,names(rnk),fixed=TRUE,value=TRUE)  ## L1000 naming allows this...
            length(gmtdx)
            ##if(length(gmtdx) < 3) { frame(); next }
            gsea.enplot( rnk, gmtdx, main=dx, cex.main=1.1, xlab="")
            nes <- round(res$NES[i],2)
            qv  <- round(res$padj[i],3)
            tt <- c( paste("NES=",nes), paste("q=",qv) )
            legend("topright", legend=tt, cex=0.9)
        }
        
    })    

    dsea_moaplot.RENDER %<a-% reactive({

        ngs <- inputData()
        req(ngs, input$dr_contrast, input$dsea_method)
        
        if(is.null(ngs$drugs)) return(NULL)
        shiny::validate(need("drugs" %in% names(ngs), "no 'drugs' in object."))    
        
        comparison=1
        comparison = input$dr_contrast
        if(is.null(comparison)) return(NULL)
        
        res <- getDseaTable()
        
        dmethod="mono"
        dmethod="combo"
        dmethod <- input$dsea_method
        
        j1 <- which( res$padj < 0.2 & res$NES > 0)
        j2 <- which( res$padj < 0.2 & res$NES < 0)
        moa.pos <- strsplit(as.character(res$moa[j1]), split="[\\|;]")
        moa.neg <- strsplit(as.character(res$moa[j2]), split="[\\|;]")
        moa <- strsplit(as.character(res$moa), split="[\\|;]")
        moa.lengths <- sapply(moa,length)

        fx <- mapply(function(x,n) rep(x,n), res$NES, moa.lengths)
        moa.avg <- sort(tapply( unlist(fx), unlist(moa), mean))
        moa.sum <- sort(tapply( unlist(fx), unlist(moa), sum))
        head(moa.pos)
        head(moa.neg)
        moa.pos <- sort(table(unlist(moa.pos)),decreasing=TRUE)
        moa.neg <- sort(table(unlist(moa.neg)),decreasing=TRUE)

        dtg.pos <- strsplit(as.character(res$target[j1]), split="[\\|;]")
        dtg.neg <- strsplit(as.character(res$target[j2]), split="[\\|;]")
        dtg <- strsplit(as.character(res$target), split="[\\|;]")
        dx <- mapply(function(x,n) rep(x,n), res$NES, sapply(dtg,length))
        dtg.avg <- sort(tapply( unlist(dx), unlist(dtg), mean))
        dtg.sum <- sort(tapply( unlist(dx), unlist(dtg), sum))    
        dtg.pos <- sort(table(unlist(dtg.pos)),decreasing=TRUE)
        dtg.neg <- sort(table(unlist(dtg.neg)),decreasing=TRUE)
        head(dtg.pos)
        head(dtg.neg)
        
        NTOP=10
        if(1) {
            moa.top <- sort(c( head(moa.pos,NTOP), -head(moa.neg,NTOP)),decreasing=TRUE)
            dtg.top <- sort(c( head(dtg.pos,NTOP), -head(dtg.neg,NTOP)),decreasing=TRUE)

            ##layout(matrix(1:2,nrow=1),widths=c(1.4,1))
            ##par(mfrow=c(2,1))
            par(mar=c(4,15,5,0.5), mgp=c(2,0.7,0))
            par(mfrow=c(1,1))
            if(input$dsea_moatype=="drug class") {
                par(mfrow=c(2,1), mar=c(4,4,1,0.5), mgp=c(2,0.7,0))
                barplot(moa.top, horiz=FALSE, las=3, ylab="drugs (n)",
                        cex.names = 0.8 )
                ##title(main="MOA", line=1 )
            } else {
                par(mfrow=c(2,1), mar=c(0,4,1,0.5), mgp=c(2,0.7,0))
                barplot(dtg.top, horiz=FALSE, las=3, ylab="drugs (n)",
                        cex.names = 0.8 )
                ##title(main="target gene", line=1 )
            }
        }
        
    })    

    dsea_table.RENDER <- reactive({
        ngs <- inputData()
        req(ngs)
        if(is.null(ngs$drugs)) return(NULL)
        
        res <- getDseaTable()
        req(res)
        res$moa <- shortstring(res$moa,60)
        res$target <- shortstring(res$target,30)
        res$drug   <- shortstring(res$drug,60)
        
        ## limit number of results??
        ##jj <- unique(c( head(order(-res$NES),250), tail(order(-res$NES),250)))
        jj <- unique(c( head(order(-res$NES),1000), tail(order(-res$NES),1000)))
        jj <- jj[order(-abs(res$NES[jj]))]
        res <- res[jj,]
        
        DT::datatable( res, rownames=FALSE,
                      class = 'compact cell-border stripe hover',                  
                      extensions = c('Scroller'),
                      selection=list(mode='single', target='row', selected=1),
                      fillContainer = TRUE,
                      options=list(
                          ##dom = 'Blfrtip', buttons = c('copy','csv','pdf'),
                          dom = 'lfrtip', 
                          scrollX = TRUE, ##scrollY = TRUE,
                          scrollY = tabH, scroller=TRUE, deferRender=TRUE
                      )  ## end of options.list 
                      ) %>%
            DT::formatStyle(0, target='row', fontSize='11px', lineHeight='70%') %>% 
                DT::formatStyle( "NES",
                                background = color_from_middle( res[,"NES"], 'lightblue', '#f5aeae'),
                                backgroundSize = '98% 88%', backgroundRepeat = 'no-repeat',
                                backgroundPosition = 'center') 
    })

    dsea_actmap.RENDER %<a-% reactive({
        require(igraph)
        ngs <- inputData()
        req(ngs, input$dr_contrast, input$dsea_method)

        shiny::validate(need("drugs" %in% names(ngs), "no 'drugs' in object."))    
        if(is.null(ngs$drugs)) return(NULL)
        
        dmethod="activity/L1000";comparison=1
        dmethod <- input$dsea_method        
        comparison = input$dr_contrast
        if(is.null(comparison)) return(NULL)
        
        nes <- ngs$drugs[[dmethod]]$X
        qv  <- ngs$drugs[[dmethod]]$Q
        score <- nes * (1 - qv)**2
        score[is.na(score)] <- 0
        if(NCOL(score)==1) score <- cbind(score,score)
        
        ## reduce score matrix
        ##score = head(score[order(-rowSums(abs(score))),],40)
        ##score = score[head(order(-rowSums(score**2)),50),] ## max number of terms
        score = score[head(order(-score[,comparison]**2),50),,drop=FALSE] ## max number of terms    
        score = score[,head(order(-colSums(score**2)),25),drop=FALSE] ## max comparisons/FC

        cat("dsea_actmap:: dim(score)=",dim(score),"\n")
        score <- score + 1e-3*matrix(rnorm(length(score)),nrow(score),ncol(score))
        d1 <- as.dist(1-cor(t(score),use="pairwise"))
        d2 <- as.dist(1-cor(score,use="pairwise"))
        d1[is.na(d1)] <- 1
        d2[is.na(d2)] <- 1
        jj=1;ii=1:nrow(score)
        ii <- hclust(d1)$order
        jj <- hclust(d2)$order
        score <- score[ii,jj,drop=FALSE]
        
        cex2=1
        colnames(score) = substring(colnames(score),1,30)
        rownames(score) = substring(rownames(score),1,50)
        if(ncol(score)>15) {
            rownames(score) = substring(rownames(score),1,40)
            cex2=0.85
        }
        if(ncol(score)>25) {
            rownames(score) = substring(rownames(score),1,30)
            colnames(score) <- rep("",ncol(score))
            cex2=0.7
        }

        par(mfrow=c(1,1), mar=c(1,1,1,1), oma=c(0,2,0,1))
        require(corrplot)
        score2 <- score
        if(input$dr_normalize) score2 <- t( t(score2) / apply(abs(score2),2,max)) 
        score2 <- sign(score2) * abs(score2/max(abs(score2)))**3   ## fudging
        bmar <- 0 + pmax((50 - nrow(score2))*0.25,0)
        corrplot( score2, is.corr=FALSE, cl.pos = "n", col=BLUERED(100),
                 tl.cex = 0.9*cex2, tl.col = "grey20", tl.srt = 45,
                 mar=c(bmar,0,0,0) )
        
    })    

    
    ##--------- DSEA enplot plotting module
    dsea_enplots.opts = tagList()
    callModule(
        plotModule,
        id = "dsea_enplots",
        func = dsea_enplots.RENDER,
        func2 = dsea_enplots.RENDER,         
        title = "Drug profile enrichment", label="a",
        info.text = "The <strong>Drug Connectivity Map</strong> correlates your signature with more than 5000 known drug profiles from the L1000 database, and shows the top N=10 similar and opposite profiles by running the GSEA algorithm on the contrast-drug profile correlation space.",
        options = dsea_enplots.opts,
        pdf.width=11, pdf.height=7,
        height = 0.54*rowH, res=72
    )
    ##outputOptions(output, "dsea_enplots", suspendWhenHidden=FALSE) ## important!!!

    
    ##---------- DSEA Activation map plotting module
    dsea_moaplot.opts = tagList(
        tipify( radioButtons(ns('dsea_moatype'),'Plot type:',c("drug class","target gene"),inline=TRUE),
               "Select plot type of MOA analysis: by class description or by target gene.")
    )
    callModule(
        plotModule,
        id = "dsea_moaplot",
        func = dsea_moaplot.RENDER,
        func2 = dsea_moaplot.RENDER, 
        title = "Mechanism of action", label="c",
        info.text = "This plot visualizes the <strong>mechanism of action</strong> (MOA) across the enriched drug profiles. On the vertical axis, the number of drugs with the same MOA are plotted. You can switch to visualize between MOA or target gene.",
        options = dsea_moaplot.opts,
        pdf.width=4, pdf.height=6,
        height = 0.54*rowH, res=72
    )

    ##-------- Activation map plotting module
    dsea_actmap.opts = tagList()
    callModule(
        plotModule,
        id = "dsea_actmap",
        func = dsea_actmap.RENDER,
        func2 = dsea_actmap.RENDER, 
        title = "Activation matrix", label="d",
        info.text = "The <strong>Activation Matrix</strong> visualizes the activation of drug activation enrichment across the conditions. The size of the circles correspond to their relative activation, and are colored according to their upregulation (red) or downregulation (blue) in the contrast profile.",
        options = dsea_actmap.opts,
        pdf.width=6, pdf.height=10,
        height = c(rowH,750), res=72
    )

    ##--------buttons for table
    dsea_table <- callModule(
        tableModule,
        id = "dsea_table", label="b",
        func = dsea_table.RENDER, 
        info.text="Drug profile enrichment table. Enrichment is calculated by correlating your signature with more than 5000 known drug profiles from the L1000 database. Because the L1000 has multiple perturbation experiment for a single drug, drugs are scored by running the GSEA algorithm on the contrast-drug profile correlation space. In this way, we obtain a single score for multiple profiles of a single drug.", 
        title = "Profile enrichment table",
        height = c(260,700)
    )
       
    ##-----------------------------------------
    ## Page layout
    ##-----------------------------------------

    dsea_analysis_caption = "<b>Drug Connectivity Map.</b> Drug CMap correlates your signature with more than 5000 known drug perturbation profiles from the L1000 database. <b>(a)</b> Figure showing the top N=10 similar and opposite profiles by running the GSEA algorithm on the contrast-drug profile correlation space. <b>(b)</b> Table summarizing the statistical results of the drug enrichment analysis. <b>(c)</b> Mechanism-of-action plot showing the top most frequent drug class (or target genes) having similar or opposite enrichment compared to the query signature. <b>(d)</b> Activation matrix visualizing enrichment levels of drug signatures across multiple contrast profiles." 

    output$DSEA_analysis_UI <- renderUI({
        fillCol(
            flex = c(1,NA),
            height = fullH,
            fillRow(
                height = rowH,
                flex = c(2.6,1), 
                fillCol(
                    flex = c(1.4,0.15,1),
                    height = rowH,
                    fillRow(
                        flex=c(2.2,1),
                        plotWidget(ns("dsea_enplots")),
                        plotWidget(ns("dsea_moaplot"))
                    ),
                    br(),  ## vertical space
                    tableWidget(ns("dsea_table"))        
                ),
                plotWidget(ns("dsea_actmap"))
            ),
            div(HTML(dsea_analysis_caption),class="caption")
        )
    })
    outputOptions(output, "DSEA_analysis_UI", suspendWhenHidden=FALSE) ## important!!!


}