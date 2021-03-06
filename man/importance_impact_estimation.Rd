% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/DiscNoise.R
\name{importance_impact_estimation}
\alias{importance_impact_estimation}
\title{Importance impact Computer
This function takes the importance values generated by the framework for data with various amounts of discretization noise. It does so by reporting the significance of the generated rank lists for classifiers constructed on data with and without the discretization noise
Furthermore, They also report the liklihood of rank shifts that occur on the top three ranks. Shifts are the possibility of the importance rank for the given rank shifting due to discretization noise}
\usage{
importance_impact_estimation(importance_results, col_names)
}
\arguments{
\item{importance_results}{a list of lists, which is result from the framework}

\item{col_names}{a vector specifying the col_names that we need to be concerned with}
}
\value{
matrix containing the interpretation impact
}
\description{
Importance impact Computer
This function takes the importance values generated by the framework for data with various amounts of discretization noise. It does so by reporting the significance of the generated rank lists for classifiers constructed on data with and without the discretization noise
Furthermore, They also report the liklihood of rank shifts that occur on the top three ranks. Shifts are the possibility of the importance rank for the given rank shifting due to discretization noise
}
