
<!-- README.md is generated from README.Rmd. Please edit that file -->

## dsb <a href='https://mattpm.github.io/dsb'><img src='man/figures/logo.png' align="right" height="150" /></a>

## An R package for normalizing and denoising CITEseq data

<!-- badges: start -->

<!-- [![Travis build status](https://travis-ci.org/MattPM/dsb.svg?branch=master)](https://travis-ci.org/MattPM/dsb) -->

<!-- badges: end -->

**please see vignettes in the “articles” tab at
<https://mattpm.github.io/dsb/> for a detailed workflow describing
reading in proper cellranger output and using the DSB normalizaiton
method**

**DSB was used in this informative preprint on optomizing CITE-seq
experiments:
<https://www.biorxiv.org/content/10.1101/2020.06.15.153080v1>**

This package was developed at [John Tsang’s
Lab](https://www.niaid.nih.gov/research/john-tsang-phd) by Matt Mulè,
Andrew Martins and John Tsang. The package implements our normalization
and denoising method for CITEseq data. The details of the method can be
found in [the biorxiv
preprint](https://www.biorxiv.org/content/10.1101/2020.02.24.963603v1.full.pdf)
We utilized the dsb package to normalize CITEseq data reported in [this
paper](https://doi.org/10.1038/s41591-020-0769-8).

As described in [the biorxiv
preprint](https://www.biorxiv.org/content/10.1101/2020.02.24.963603v1.full.pdf)
comparing unstained control cells and empty droplets we found that a
major contributor to background noise in protein expression data is
unbound antibodies captured and sequenced in droplets. DSB corrects for
this background by leveraging empty droplets, which serve as a “built
in” noise measurement in droplet capture single cell experiments
(e.g. 10X, dropseq, indrop). In addition, we define a per-cell
denoising covariate to account for several potential sources of
technical differences among single cells – see our preprint for details.

## installation

You can install the released version of dsb in your R session with the
command
below

``` r
# this is analagous to install.packages("package), you need the package devtools to install a package from a github repository like this one. 
require(devtools)
devtools::install_github(repo = 'MattPM/dsb')

# load dsb like any other R package 
library(dsb)
```

# Run DSB on example data

``` r
norm_mtx = DSBNormalizeProtein(cell_protein_matrix = cells_citeseq_mtx, empty_drop_matrix = empty_drop_citeseq_mtx)
```

# Quick start using *RAW* 10X cellranger output

load public 10X CITE-seq data \#\#\# downloaded the *feature /
cellmatrix raw* file from here:
<https://support.10xgenomics.com/single-cell-gene-expression/datasets/3.0.2/5k_pbmc_protein_v3>

``` r
library(dsb)
library(Seurat) # version 3 in example provided belo
library(tidyverse)
library(magrittr)
path_to_data = "data/10x_data/10x_pbmc5k_V3/raw_feature_bc_matrix/"
raw = Read10X(data.dir = path_to_data)

# create object with Minimal filtering (retain drops with 5 unique mRNAs detected)
s1 = CreateSeuratObject(counts = raw$`Gene Expression`,  min.cells = 10, min.features = 5)

# add some metadata 
s1$log10umi = log10(s1$nCount_RNA  + 1) 
s1$bc = rownames(s1@meta.data)

# define negative and positive drops based on an mRNA threshold to define neg and positive cells (see details below) 
hist(log10(s1$nCount_RNA  + 1), breaks = 1000)
neg_drops = s1@meta.data %>% filter(log10umi > 1.5 & log10umi < 2.79) %$% bc
positive_cells = s1@meta.data %>% filter(log10umi > 2.8 & log10umi < 4.4) %$% bc
  
# Subset protein data to create a standard R matrix of protein counts for negative droplets and cells 
neg_prot = raw$`Antibody Capture`[ ,  neg_drops ] %>% as.matrix()
positive_prot = raw$`Antibody Capture`[ , positive_cells] %>% as.matrix()

# run DSB normalization
isotypes = rownames(positive_prot)[30:32]
mtx = DSBNormalizeProtein(cell_protein_matrix = positive_prot,
                           empty_drop_matrix = neg_prot,
                           denoise.counts = TRUE, use.isotype.control = TRUE, 
                           isotype.control.name.vec = isotypes)

## subset the raw data to only iinclude cell containing drops and add protein data 
s = subset(s1, cells = colnames(mtx))
s[["CITE"]] = CreateAssayObject(counts = positive_prot)
s = SetAssayData(s,assay = "CITE", slot = "data",new.data = mtx)

# Done! you can also save the resulting normalized matrix for integration with scanpy etc
write_delim(mtx, path = paste0(path_to_data, "dsb_norm_matrix.txt"),delim = "\t" )
```

# Recommended next steps in CITEseq workflow. Protein based clustering and protein based based cluster annotation

This is the same process followed in our paper
<https://www.nature.com/articles/s41591-020-0769-8>

DSB normalized vlaues provide a straightforward comparable value for
each protein in each cluster. They are the denoised log number of
standard deviations from the background.

``` r

# Get dsb normalized protein data without isotype controls for clustering
s_dsb = s@assays$CITE@data
s_dsb = s_dsb[1:29, ]

# defint euclidean distance matrix and cluster 
p_dist = dist(t(s_dsb))
p_dist = as.matrix(p_dist)
s[["p_dist"]] <- FindNeighbors(p_dist)$snn
s = FindClusters(s, resolution = 0.6, graph.name = "p_dist")

# Plot clusters by average protein expression for annotation 

adt_data = cbind(as.data.frame(t(s@assays$CITE@data)), s@meta.data)
prots = rownames(s@assays$CITE@data)
adt_plot = adt_data %>% 
    group_by(seurat_clusters) %>% 
    summarize_at(.vars = prots, .funs = mean) %>% 
    column_to_rownames("seurat_clusters") %>% 
    t %>% 
    as.data.frame

pheatmap::pheatmap(adt_plot, color = viridis::viridis(25, option = "B"), fontsize_row = 8)
```

![](images/cluster_average_dsb.png)

# More information: How were background drops defined in the quick example above?

First apply some minimal (RNA based in this case) filtering to retain
noise / empty droplets for DSB. Below the cells that should be used for
background in this experiment are shown in a histogram of the droplets
passing a minimal filtering step.

``` r

path_to_data = "data/10x_data/10x_pbmc5k_V3/raw_feature_bc_matrix/"
raw = Read10X(data.dir = path_to_data)

# create object with Minimal filtering (retain drops with 5 unique mRNAs detected)
s1 = CreateSeuratObject(counts = raw$`Gene Expression`,  min.cells = 10, min.features = 5)

# define number of total drops (>130K) after minimal filtering
ndrop = dim(s1@meta.data)[1]

# Plot
hist_attr = list(  theme_bw() , theme(text = element_text(size = 8)) , geom_density(fill = "#3e8ede") )
p1 = ggplot(s1@meta.data, aes(x = log10(nCount_RNA + 1 ) )) +
  hist_attr + 
  ggtitle(paste0( " raw_feature_bc_matrix: ", ndrop, " droplets")) + 
  geom_vline(xintercept = c(2.8, 1.4 ),   linetype = "dashed") + 
  annotate("text", x = 1, y=1.5, label = " region 1: \n void of data ") + 
  annotate("text", x = 2, y=2, label = " region 2: \n background drops \n define 'empty_drop_matrix' \n with these drops ") + 
  annotate("text", x = 4, y=2, label = " region 3: \n cell containing droplets \n zomed in on next plot") 


p2 = ggplot(s1@meta.data %>% filter(log10(nCount_RNA + 1) > 2.8), aes(x = log10(nCount_RNA + 1 ) )) +
  hist_attr + 
  ggtitle(paste0(" drops containing cells "))  
p3 = cowplot::plot_grid( p1 , p2 ) 
p3
```

![](images/drop_distribition.png)

If there were no isotype controls in the example above, the call would
have been:

``` r
mtx = DSBNormalizeProtein(cell_protein_matrix = pos_prot,
                          empty_drop_matrix = neg_prot,
                          denoise.counts = TRUE,
                          use.isotype.control = FALSE)
```

## Quickstart 2 using example data; removing background as captured by data from empty droplets

``` r
# load package and normalize the example raw data 
library(dsb)
# normalize
normalized_matrix = DSBNormalizeProtein(cell_protein_matrix = cells_citeseq_mtx,
                                        empty_drop_matrix = empty_drop_citeseq_mtx)
```

## Quickstart 3 using example data; – removing background and correcting for per-cell technical factor as a covariate

By default, dsb defines the per-cell technical covariate by fitting a
two-component gaussian mixture model to the log + 10 counts (of all
proteins) within each cell and defining the covariate as the mean of the
“negative” component. We recommend also to use the counts from the
isotype controls in each cell to compute the denoising covariate
(defined as the first principal component of the isotype control counts
and the “negative” count inferred by the mixture model above.)

``` r

# define a vector of the isotype controls in the data 
isotypes = c("Mouse IgG2bkIsotype_PROT", "MouseIgG1kappaisotype_PROT",
             "MouseIgG2akappaisotype_PROT", "RatIgG2bkIsotype_PROT")

normalized_matrix = DSBNormalizeProtein(cell_protein_matrix = cells_citeseq_mtx,
                                        empty_drop_matrix = empty_drop_citeseq_mtx,
                                        use.isotype.control = TRUE,
                                        isotype.control.name.vec = isotypes)
```

## Visualization on example data: distributions of CD4 and CD8 DSB normalized CITEseq data.

**Note, there is NO jitter added to these points for visualization;
these are the unmodified normalized
counts**

``` r
# add a density gradient on the points () this is helpful when there are many thousands of cells )
# this density function is from this blog post: https://slowkow.com/notes/ggplot2-color-by-density/
get_density = function(x, y, ...) {
  dens <- MASS::kde2d(x, y, ...)
  ix <- findInterval(x, dens$x)
  iy <- findInterval(y, dens$y)
  ii <- cbind(ix, iy)
  return(dens$z[ii])
}

library(ggplot2)
data.plot = normalized_matrix %>% t %>%
  as.data.frame() %>% 
  dplyr::select(CD4_PROT, CD8_PROT, CD27_PROT, CD19_PROT) 

density_attr = list(
  geom_vline(xintercept = 0, color = "red", linetype = 2), 
  geom_hline(yintercept = 0, color = "red", linetype = 2), 
  theme(axis.text = element_text(face = "bold",size = 12)) , 
  viridis::scale_color_viridis(option = "B"), 
  scale_shape_identity(), 
  theme_bw() 
)


data.plot = data.plot %>% dplyr::mutate(density = get_density(data.plot$CD4_PROT, data.plot$CD8_PROT, n = 100)) 
p1 = ggplot(data.plot, aes(x = CD8_PROT, y = CD4_PROT, color = density)) +
  geom_point(size = 0.5) + density_attr +  ggtitle("small example dataset")

data.plot = data.plot %>% dplyr::mutate(density = get_density(data.plot$CD19_PROT, data.plot$CD27_PROT, n = 100)) 
p2 = ggplot(data.plot, aes(x = CD19_PROT, y = CD27_PROT, color = density)) +
  geom_point(size = 0.5) + density_attr + ggtitle("small example dataset")

cowplot::plot_grid(p1,p2)
```

<img src="man/figures/README-unnamed-chunk-9-1.png" width="100%" />

## How do I get the empty droplets?

If you don’t have hashing data, you can define the negative drops as
shown above in the vignette using 10X data. If you have hashing data,
demultiplexing functions define a “negative” cell population which can
be used to define background.

HTODemux function in Seurat:
<https://satijalab.org/seurat/v3.1/hashing_vignette.html>

deMULTIplex function from Multiseq (this is now also implemented in
Seurat). <https://github.com/chris-mcginnis-ucsf/MULTI-seq>

In practice, you would want to confirm that the cells called as
“negative” indeed have low RNA / gene content to be certain that there
are no contaminating cells. Also, we recommend hash demultiplexing with
the *raw* output from cellranger rather than the processed output
(i.e. outs/raw\_feature\_bc\_matrix). This output contains all barcodes
and will have more empty droplets from which the HTODemux function will
be able to estimate the negative distribution. This will also have the
benefit of creating more empty droplets to use as built-in protein
background controls in the DSB function.

**see 10x data vignette discussed above and shown here
<https://github.com/MattPM/dsb/issues/9> ** **please see vignettes in
the “articles” tab at <https://mattpm.github.io/dsb/> for a detailed
workflow detailing these
steps**

## Simple example workflow (Seurat Version 3) for experiments with Hashing data

``` r

# get the ADT counts using Seurat version 3 
seurat_object = HTODemux(seurat_object, assay = "HTO", positive.quantile = 0.99)
Idents(seurat_object) = "HTO_classification.global"
neg_object = subset(seurat_object, idents = "Negative")
singlet_object = subset(seurat_object, idents = "Singlet")


# non sparse CITEseq data actually store better in a regular materix so the as.matrix() call is not memory intensive.
neg_adt_matrix = GetAssayData(neg_object, assay = "CITE", slot = 'counts') %>% as.matrix()
positive_adt_matrix = GetAssayData(singlet_object, assay = "CITE", slot = 'counts') %>% as.matrix()


# normalize the data with dsb
# make sure you've run devtools::install_github(repo = 'MattPM/dsb')
normalized_matrix = DSBNormalizeProtein(cell_protein_matrix = positive_adt_matrix,
                                        empty_drop_matrix = neg_adt_matrix)


# now add the normalized dat back to the object (the singlets defined above as "object")
singlet_object = SetAssayData(object = singlet_object, slot = "CITE", new.data = normalized_matrix)
```

## Simple example workflow Seurat version 2 for experiments with hashing data

``` r

# get the ADT counts using Seurat version 3 
seurat_object = HTODemux(seurat_object, assay = "HTO", positive.quantile = 0.99)

neg = seurat_object %>%
  SetAllIdent(id = "hto_classification_global") %>% 
  SubsetData(ident.use = "Negative") 

singlet = seurat_object %>%
  SetAllIdent(id = "hto_classification_global") %>% 
  SubsetData(ident.use = "Singlet") 

# get negative and positive ADT data 
neg_adt_matrix = neg@assay$CITE@raw.data %>% as.matrix()
pos_adt_matrix = singlet@assay$CITE@raw.data %>% as.matrix()


# normalize the data with dsb
# make sure you've run devtools::install_github(repo = 'MattPM/dsb')
normalized_matrix = DSBNormalizeProtein(cell_protein_matrix = pos_adt_matrix,
                                        empty_drop_matrix = neg_adt_matrix)


# add the assay to the Seurat object 
singlet = SetAssayData(object = singlet, slot = "CITE", new.data = normalized_matrix)
```
