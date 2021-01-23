dsbmessage <- function()
{
  mesg <-
    c(
    "dsb package for CITE-seq protein normalization loaded ",
    "please cite our paper at: https://www.biorxiv.org/content/10.1101/2020.02.24.963603v1 ",
    "see vignette at https://github.com/niaid/dsb"
    )
  return(mesg)
}

.onAttach <- function(lib, pkg)
{
  # startup message
  msg <- dsbmessage()
  if(!interactive())
  msg[1] <- paste("Package 'dsb' version", packageVersion("dsb"))
  packageStartupMessage(msg)
  invisible()
}
