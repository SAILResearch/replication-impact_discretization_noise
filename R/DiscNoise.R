library(randomForest)
library(pROC)
library(ROCR)
library(doMC)
library(data.table)
library(rms)
library(caret)
library(mccr)


#Extract importance from the models
#' Function for generating the importance values of the classifiers 
#'@param model a r model. A trained classifier model whose importance is to be evaluated
#'@param column_names a character vector, containing the columnames of the test data set
#'@param classifier The classifier for which the importance is to be computed. Currently supported types are 'rf','C5.0','glm','knn'
#'@return a numeric vector, with all the importance values for the features involved
#'@export

get_importance_generic<-function(model,column_names,classifier){
  if(classifier=='rf'){
    
    return(randomForest:::importance(model$finalModel)[,'MeanDecreaseGini'])
  }else if(classifier=='C5.0'){
    
    m<-varImp(model)$importance
    m$class2<-NULL
    importance_vector<-rep(0,length(column_names))
    names(importance_vector)<-column_names
    rownames(m)<-gsub("`","",rownames(m))
    importance_vector[rownames(m)]<-m$Overall
    return(importance_vector)
  }
  
  
  
  else if(classifier=='glm'){
    
    m<-varImp(model)$importance
    m$class2<-NULL
    importance_vector<-rep(0,length(column_names))
    names(importance_vector)<-column_names
    rownames(m)<-gsub("`","",rownames(m))
    importance_vector[rownames(m)]<-m$Overall
    return(importance_vector)
  }
  else if(classifier =='knn'){
    
    m<-varImp(model)$importance
    m$class2<-NULL
    importance_vector<-rep(0,length(column_names))
    names(importance_vector)<-column_names
    rownames(m)<-gsub("`","",rownames(m))
    importance_vector[column_names%in%rownames(m)]<-m[,1]
    return(importance_vector)
    
  }
  
}

### Generating OOSB samples 
#' The function generates the out-of-sample bootstrap train and test data
#' A function to compute Area Under the ROC-CURVE 
#' @param data must be a object of type data.frame, with the continuous dependent variable
#' @param boot_size a numeric value. It specifies the number of bootstrap iterations to be used in the framework.
#' @param seed a logical value indicating if the experiment needs to repetable or random. Defaults to TRUE
#' @return a list containing train and test data for all specified boot_Size iterations
#' @export

create_oosb_sample<-function(data,boot_size,seed=TRUE){
  
  train_indices <- list()
  test_indices <- list()
  
  #For reproducability
  if(is.numeric(seed)){
    set.seed(seed)
  }else if(seed==TRUE){
    set.seed(42)
  }else{
    seed<-FALSE
  }
  
  for(count in 1:boot_size){
    data <- data[sample(nrow(data)),]
    train_index<-sample(seq(1:nrow(data)),size=nrow(data),replace=T)
    test_index<-seq(1:nrow(data))[-train_index]
    
    train_indices[[count]]<-train_index
    test_indices[[count]]<-test_index
  }
  
  return(list(train_indices,test_indices))
  
}

#' Extract AUC Function
#' A function to compute Area Under the ROC-CURVE 
#' @param actuals A vector containing the true class of the test data points
#' @param predicted A vector of predicted values 
#' @return a numeric copmuted MCC value
#' @export

get_auc<-function(actuals,predicted){
  predictions<-prediction(predicted,actuals)
  
  auc<-ROCR::performance(predictions,'auc')
  auc<-unlist(slot(auc,'y.values'))
  result_auc<-min(round(auc,digits=2))
  return(result_auc)
}

#' A function to compute Mathew's Correlation Coefficient
#' @param act A vector containing the true class of the test data points
#' @param pred A vector of predicted values 
#' @param classes The classes that are existent in the dependent variable 
#' @return a numeric copmuted MCC value
#' @export

#Function to get Mathew's Correlation Coefficient 
get_mcc<-function(act,pred,classes)
{
  TP <- sum(act == classes[1] & pred == classes[1])
  TN <- sum(act == classes[2] & pred == classes[2])
  FP <- sum(act == classes[2] & pred == classes[1])
  FN <- sum(act == classes[1] & pred == classes[2])
  denom <- as.double(TP + FP) * (TP + FN) * (TN + FP) * (TN + 
                                                           FN)
  if (any((TP + FP) == 0, (TP + FN) == 0, (TN + FP) == 0, (TN + 
                                                           FN) == 0)) 
    denom <- 1
  mcc <- ((TP * TN) - (FP * FN))/sqrt(denom)
  return(mcc)
}

#'The function that is responsible for computing the performance evaluation metrics
#'
#'@param actuals A vector containing the true class of the test data points
#'@param test a dataframe. Test dataset 
#'@param model a r model. A trained classifier model whose performance is to be evaluated
#'@return a vector with al the performance measures computed 
#'@export

#This function computes all the performance metrics at once 
get_performance_metrics<-function(actuals,test,model)
{
  predicted_response <- predict_generic(model,test,type='response')
  classes<-unique(predicted_response)
  print(classes)
  
  predicted_probablity <- predict_generic(model,test, type='prob')
  
  
  if(length(classes)==2){
    #Accuracy
    accuracy <- length(predicted_response[predicted_response==actuals])/length(actuals)
    #Precision
    precision <- precision(data=predicted_response,reference=actuals,relevant='class1')
    #Recall
    recall <- recall(data=predicted_response,reference=actuals,relevant='class1')
    #Brier Score
    brier_score <- mean((predicted_probablity-(as.numeric(actuals)-1))^2)
    #AUC
    auc<-get_auc(actuals,predicted_probablity[,2])
    #F-Measure
    f_measure<-F_meas(data=predicted_response,reference = actuals)
    #Mathew's Correlation Co-efficient 
    mcc <- get_mcc(actuals,predicted_response,classes)
    
    return(c(accuracy,precision,recall,brier_score,auc,f_measure,mcc))
  }
   else{
   stop(paste0('We only support binary classifiers for now, the dependent variable has more than two outcome classes'))
   }
}


#' This is an internal function that builds the classifier model 
#' @param classifier a string, takes the name of the classifier.Currently supported classifiers are 
#' 'rf' - Random forest
#' 'lrm' - Logistic regression
#' 'CART' - Classification tree
#' 'knn' - K-Nearest Neighbors 
#' @param train a dataframe. Contains the train dataset
#' @bestTune is the tuned hyper parameters of the model that needs to used for the model construction
#' @param ... optional additional arguements for the classifer
#' @export

build_model<-function(classifier,train,bestTune,...){

    model<-caret:::train(response~.,data=train,method=classifier,trControl=trainControl(classProbs=TRUE,allowParallel=FALSE,method='none',seeds=10),tuneGrid=bestTune)
    return(model)
    
  }


#' Abstracting the predict function 
#' @param model r model object, passed to generate actual responses or probability scores 
#' @param test the test dataset for which prob score or responses are to be genereated 
#' @param type a string, that takes either c('class','prob','response') for apporiate response
#' @return probability score for the outcome classes or actual class that the supplied model predicts
#' @export
predict_generic<-function(model,test,type)
{
  if(type=='response')
  {
    return(predict(model,newdata=test,type='raw')) 
  }
  
  if(type=='prob')
  {
    return(predict(model,newdata=test,type='prob'))
  }
  
}

remove_noise<-function(train,dep_var,cutpoint,target){
  
  return(train[(train[,dep_var]<cutpoint-target)|(train[,dep_var]>cutpoint+target),])
}

#' Hyper parameter tuning function
#' #' 
#' @param classifier a string, takes the name of the classifier.Currently supported classifiers are 
#' 'rf' - Random forest
#' 'lrm' - Logistic regression
#' 'CART' - Classification tree
#' 'knn' - K-Nearest Neighbors 
#' @param train data frame to be used for hyper parameter tuning 
#' @param n_cores No of cores to be used for the process of hyper parameter optimization
#' 
tune_hyper_parameters<-function(classifier,train,n_cores){
  registerDoParallel(n_cores)
  model<-caret:::train(response~.,data=train,method=classifier,trControl=trainControl(classProbs=TRUE,allowParallel=TRUE))
  return(model$bestTune)
}
#' RWKH framework
#' This framework does the heavy lifting of computing the performance and featue importance using out-o-sample boostrap validation for a given data configuration
#' 
#' 
#' @param classifier a string, takes the name of the classifier.Currently supported classifiers are 
#' 'rf' - Random forest
#' 'lrm' - Logistic regression
#' 'CART' - Classification tree
#' 'knn' - K-Nearest Neighbors 
#' @param data must be a object of type data.frame, with the continuous dependent variable
#' @param parallel a logical value indicating if the function must be executed in parallel --Recommended.
#' @param n_cores a numeric value specifying the number of cores to be used for parallel execution. Defaults to 1.
#' @param boot_size a numeric value. It specifies the number of bootstrap iterations to be used in the framework. Defaults to 100
#' @param dep_var a string giving the column name of continuous dependent variable supplied in the data parameter. This is the variable which creates the discretization noise.
#' @param target a numeric value indicating the amount of discretization noise is to be included relative to cutpoint' 
#' @return a list, that contains two lists containing performance impacts and importance values for each bootstrap iteration for the classifier
#' @export
RWKH_framework<-function(classifier,data,parallel,n_cores,boot_size,dep_var,cutpoint,target,...)
{
  indices<-create_oosb_sample(data,boot_size+1)
  train_indices<-indices[[1]]
  test_indices<-indices[[2]]
  data_copy<-data
  data_copy[,c('res','response')]<-NULL
  bestTune<-tune_hyper_parameters(classifier,data[train_indices[[boot_size+1]],],n_cores)
  if(parallel<-TRUE){
    
    registerDoMC(n_cores)
    results<-foreach(i=1:boot_size,.combine=c,.multicombine=TRUE,.packages=c('randomForest.ddR','pROC','ROCR','caret'))%dopar%{
      
      train<-data[train_indices[[i]],]
      train<-remove_noise(train,dep_var,cutpoint,target)
      
      test<-data[test_indices[[i]],]
      
      train[,dep_var]<-NULL
      test[,dep_var]<-NULL
      #constructiong model
      model<-build_model(classifier,train,bestTune)
      actuals<-test$response
      test$response<-NULL
      
      #predicted<-predict_generic
     # predicted<-predict_generic(model,test,type='prob')
      
      #Colnames extraction from design matrix
      train$response<-NULL
      if(classifier!='knn'){
      column_names<-colnames(model.matrix(~.,data=data_copy))[!colnames(model.matrix(~.,data=data_copy))%in%c("(Intercept)")]
      }else{
        column_names<-colnames(train)[!colnames(train)%in%c(dep_var,'response')]
      }
      list(list(get_performance_metrics(actuals,test,model),get_importance_generic(model,column_names,classifier)))
      #list(list(get_auc(actuals,predicted),get_importance(model,colnames(test))))
    }
    return(results)
  }else{
    
    
    results<-list()
    for(i in 1:boot_size){
      
      
      train<-data[train_indices[[i]],]
      train<-remove_noise(train,dep_var,cutpoint,target)
      
      test<-data[test_indices[[i]],]
      
      train[,dep_var]<-NULL
      test[,dep_var]<-NULL
      #constructiong model
      model<-build_model(classifier,train,bestTune)
      actuals<-test$response
      test$response<-NULL
      
      #predicted<-predict_generic
      # predicted<-predict_generic(model,test,type='prob')
      
      #Colnames extraction from design matrix
      train$response<-NULL
      if(classifier!='knn'){
        column_names<-colnames(model.matrix(~.,data=data_copy))[!colnames(model.matrix(~.,data=data_copy))%in%c("(Intercept)")]
      }else{
        column_names<-colnames(train)[!colnames(train)%in%c(dep_var,'response')]
      }
      
      results[[i]]<-list(get_performance_metrics(actuals,test,model),get_importance_generic(model,column_names,classifier))
      
    }
    
    return(results)
  }
}


#'Importance impact Computer
#'This function takes the importance values generated by the framework for data with various amounts of discretization noise. It does so by reporting the significance of the generated rank lists for classifiers constructed on data with and without the discretization noise
#'Furthermore, They also report the liklihood of rank shifts that occur on the top three ranks. Shifts are the possibility of the importance rank for the given rank shifting due to discretization noise
#'
#'@param importance_results a list of lists, which is result from the framework
#'@param col_names a vector specifying the col_names that we need to be concerned with 
#'@return matrix containing the interpretation impact
#'@export


importance_impact_estimation<-function(importance_results,col_names){
  
  #code to filter out 0 importance values when considering 
  
  redundancy_removed<-do.call(rbind,lapply(importance_results, function (x) x))
  columns_to_be_removed<-apply(redundancy_removed,2,function(x) ifelse(length(unique(x))>1,TRUE,FALSE))
  col_names<-col_names[columns_to_be_removed]
  
  
  ranks<-do.call(rbind,lapply(importance_results,function(x){
    x<-x[,c(col_names)]
    duplicates<-which(duplicated(t(x)))
    for( dup in duplicates){
      x[,dup]<-x[,dup]+sample(runif(100,0,1),1)
    }
    rank_list<-sk_esd(x)$groups
    rank_list[match(colnames(importance_results[[1]]),colnames(rank_list))]
    return(rank_list)}))
  
  #result<-ranks[,names(sort(apply(ranks,2,median)))]
  
  
  
  dx<-abs(ranks[1,]-ranks[nrow(ranks),])
  null_distribution<-rep(0,length(dx))
  
  wilcox_result<-wilcox.test(null_distribution,dx,paired=TRUE)$p.value
  co<-cohen.d(null_distribution,dx)
  
  prob_frame<-matrix(nrow=100,ncol=ncol(ranks))
  for(i in 1:100){
    #bootstrapping the scott-knott ranks
    b_samp<-apply(ranks,2,function(x) sample(x,length(x),replace=TRUE))
    duplicates<-which(duplicated(t(b_samp)))
    for( dup in duplicates){
    b_samp[,dup]<-b_samp[,dup]+sample(runif(100,0,1),1)
    }
    second_level_ranks<-sk_esd(-b_samp,alpha = 0.05)$groups
    
    prob_frame[i,]<-second_level_ranks[match(col_names,names(second_level_ranks))]

  }
  colnames(prob_frame)<-col_names
  
  #Calculating the actual likihood
  
  liklihood_shifts<-NULL
  
  prob_frame<-prob_frame[,order(apply(prob_frame,2,median))]
  temp<-prob_frame[,1:3]
  for(i in 1:3)
  {
    medians<-apply(temp,2,median)
    
    liklihood_shifts<- (c(liklihood_shifts,length(temp[,i][temp[,i]!=medians[i]])/length(temp[,i])) )
    #shift_ranges<-c(shift_ranges,length(unique(temp[,i])))
    
  }
  names(liklihood_shifts)<-c('rank1','rank2','rank3')
  Importance_impact<-matrix(nrow=1,ncol=5)
  
  
  Importance_impact[1,1]<-wilcox_result
  Importance_impact[1,2]<-paste(co$magnitude,co$estimate,sep=' ')
  Importance_impact[1,3]<-liklihood_shifts[1]
  Importance_impact[1,4]<-liklihood_shifts[2]
  Importance_impact[1,5]<-liklihood_shifts[3]
  colnames(Importance_impact)<-c('Significane','Effect Size','Rank1','Rank2','Rank3')
  return(Importance_impact)
}




#'A framework for analyzing the impact of discretization noise on the performance and impact of classifiers
#'
#'The impact on the performance of the chosen classifier is given in terms of Accuracy, Precision, Recall, Brier Score, AUC, F-Measure and Mathew's Correlation Coefficient (MCC)
#'Whereas the impact on the feature importance is given in terms of Likelihood of rank shifts
#'
#' @param data must be a object of type data.frame, with the continuous dependent variable
#' @param dep_var a string giving the column name of continuous dependent variable supplied in the data parameter. This is the variable which creates the discretization noise.
#' @param classifier a string, takes the name of the classifier.Currently supported classifiers are 
#' 'rf' - Random forest
#' 'lrm' - Logistic regression
#' 'CART' - Classification tree
#' 'knn' - K-Nearest Neighbors 
#' @param limit a numeric value specifying the limit value to demarcate user/domain expert defined noisy area in the data. Typically limit determines the amount of data around the cutpoint being defined as the noisy area.
#' @param step_size a numeric value determining in what steps must the noisy area impact must be analyzed. For faster runs, choose a larger step size, whereas for more accurate impact estimation use a smaller step-size.
#' @param parallel a logical value indicating if the function must be executed in parallel --Recommended.
#' @param n_cores a numeric value specifying the number of cores to be used for parallel execution. Defaults to 1.
#' @param boot_size a numeric value. It specifies the number of bootstrap iterations to be used in the framework. Defaults to 100
#' @param cutpoint a numeric value specifying the cutpoint to be used for discretizing the continuous dependent variable. This is the cutpoint around which discretization noise is to be analyzed. If not specified, median of the dependent variable is used as the cutpoint
#' @param save_interim_results a logical value specifying if the intermediate performance and interpretation results are to be saved. Defaults to FALSE
#' @param dest_path a string value specifying the desitination path in which the intermediate resutls are to be saved
#' @return Returns a list constaining the performance and interpretation impact. Individual elemets of list are matrices
#' @export

compute_impact<-function(data,dep_var,classifier,limit,step_size,
                         parallel=FALSE,
                         n_cores=1,boot_size=100,
                         cutpoint=NULL,save_interim_results=FALSE,dest_path=NULL){
  
  
  
  
  if(missing(dep_var)){
    stop('dependent variable column name needs to be sepcified')
  }
  
  if(missing(limit))
  {
    stop('Limit value must be specified, so that the framework can demarcate the noisy area')
  }
  
  if(missing(step_size))
  {
    stop('Choose a step size to form the increments to analyze the discretization noise in the noisy area')
  }
  
  if(parallel==TRUE)
  {
    if(missing(n_cores)){
      stop('n_cores must be specified if you set the framework to run in parallel. *Highly advised as parallel excution will dramatically reduce runtime*')
    }
  }
  
  if(missing(boot_size))
  {
    boot_size<-100
  }
  #Use the user provided cutpoint if provided. If not use median of the response variable as the cutpoint
  if(is.null(cutpoint)){
    
    
    cutpoint<-median(data[,dep_var])
    
  }else if(is.numeric(cutpoint)){
    cutpoint
  }else{
    
    stop('The cutpoint needs to be numeric or specified as NULL, cannot have cutpoints of other classes')
  }
  
  if(!(classifier %in% c('rf','glm','C5.0','knn')))
  {
    stop('The framework only supports Radom Forest, Logistic Regression, CART and KNN classifiers, Other classifiers coming soon') 
  }
  
  if(save_interim_results==TRUE)
  {
    if(missing(dest_path))
    {
      stop('To save the interim results, a destination path must be pro')
    }
  }
  
  sequence<-seq(0,limit,by=step_size)
  print(dep_var)
  print(cutpoint)
  response<-as.factor(ifelse(data[,dep_var]<=cutpoint,'class1','class2'))
  data<-cbind(data,response)
  
  performance_results<-list()
  importance_results<-list()
  
  for(percentage in sequence)
  {
    
    target<-cutpoint*(percentage/100)
    

    results<-RWKH_framework(classifier,data,parallel,n_cores,boot_size,dep_var,cutpoint,target)
    
    metrics<-do.call('rbind',lapply(results,function(x) x[[1]]))
    colnames(metrics)<-c('accuracy','precision','recall','brier_score','auc','f_measure','mcc')
    performance_results[[as.character(percentage)]]<-metrics
    print(percentage)
    imp<-do.call('rbind',lapply(results,function(x) x[[2]]))
    importance_results[[as.character(percentage)]]<-imp
    
  }
  
  if(save_interim_results==TRUE){
    saveRDS(performance_results,paste(dest_path,'/',classifier,'_performance_cartsplit.rds',sep=''))
    saveRDS(importance_results,paste(dest_path,'/',classifier,'_importance_cartsplit.rds',sep=''))
  }
  
  h<-head(sequence,1)
  t<-tail(sequence,1)
  stub1<-performance_results[[as.character(h)]]
  stub2<-performance_results[[as.character(t)]]
  
  titles<-c('accuracy','precision','recall','brier_score','auc','f_measure','mcc')
  Performance_impact<-matrix(nrow=7,ncol=4)
  for(k in 1:7){
    
    Performance_impact[k,1]<-titles[k]
    Performance_impact[k,2]<-round(100-(median(stub1[,k])/median(stub2[,k]))*100,2)
    Performance_impact[k,3]<-ifelse(wilcox.test(stub1[,k],stub2[,k],paired = FALSE)$p.value <0.05,'Significant','Not-Significant')
    Performance_impact[k,4]<-paste(as.character(cohen.d(stub1[,k],stub2[,k])$estimate),as.character(cohen.d(stub1[,k],stub2[,k])$magnitude),sep=' ')
  }
  
  if(classifier!='knn'){
  data<-data[,colnames(data)[!colnames(data)%in%c(dep_var,'response')]]
  col_names<-colnames(model.matrix(~.,data=data))
  col_names<-col_names[!col_names%in%c("(Intercept)")]
  }else{
    col_names<-colnames(data)[!colnames(data)%in%c(dep_var,'response')]
  }
  Importance_impact<-importance_impact_estimation(importance_results,col_names) 
  
  return(list(Performance_impact,Importance_impact))
  
}





