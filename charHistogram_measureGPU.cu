#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#define BIN_DIM 256
#define BUFFERSIZE 4096


// Function to check CUDA errors
#define CHECK(call) \
{ \
    const cudaError_t error = call; \
    if (error != cudaSuccess) \
    { \
        printf("Error: %s:%d, ", __FILE__, __LINE__); \
        printf("code: %d, reason: %s\n", error, cudaGetErrorString(error)); \
        exit(1); \
    } \
}

// Function to measure time in seconds
double cpuSecond() {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return ((double)ts.tv_sec + (double)ts.tv_nsec * 1.e-9);
}


// Check if CPU and GPU results match
void checkResult(unsigned long long *hostRef, unsigned long long *gpuRef, const int size) {
    bool match = 1;
    for (int i = 0; i < size; i++) {
        if ((hostRef[i] - gpuRef[i]) != 0) {
            match = 0;
            printf("Arrays do not match!\n");
            printf("host %llu gpu %llu at current %d\n", hostRef[i], gpuRef[i], i);
            
        }
    }
    if (match) printf("Arrays match !!!!\n\n");
}

// Kernel
__global__ void countCharOnGPU(char *file, unsigned long long *bin, long int size){
    unsigned int ix = threadIdx.x + blockIdx.x * blockDim.x; 
   

    if (ix < size){
        unsigned int idx = ix; // unsigned int idx = iy * W + ix;
        atomicAdd(&bin[(unsigned char)file[idx]], 1ULL);
    } 
}

// Host function for char histogram
void countCharOnCPU(char *file, unsigned long long  *bin, long int size) {
  for (int i = 0; i < size; i++) {  
      bin[(unsigned char)file[i]]++;
  }
}



int main(int argc, char **argv) {


    DIR *dir;
    struct dirent *dd;

    int fptr;
    char buffer[BUFFERSIZE];
    char result_file[4096];
    char result_dir[1024];
    char path[BUFFERSIZE];
    
    int dataType = 0;
    long int file_size ;
    char *file_host;
    unsigned long long *gpuRef, *hostRef;
    int nread, index;






    char dirname[256];
    if(argc < 3){
        printf("Usage: %s <directory_name> <data_Type_1_or_2>\n", argv[0]);
        return 1;
    }
    strcpy(dirname, argv[1]);
    dataType = atoi(argv[2]);


    if(dataType == 1){
        snprintf(result_dir, sizeof(result_dir), "results_gpu_uniform_data");
        if (mkdir("./results_gpu_uniform_data", 0777) == 0) {
            printf("Uniform data directory created successfully!\n");
        } else {
            perror("Error creating uniform data directory:");
        }
    }
    else if(dataType == 2){
        snprintf(result_dir, sizeof(result_dir), "results_gpu_normal_data");
        if (mkdir("./results_gpu_normal_data", 0777) == 0) {  
            printf("Normal data directory created successfully!\n");
        } else {
            perror("Error creating normal data directory:");
        }
    }
    else{
        printf("Usage: %s <directory_name> <data_Type_1_or_2>\n", argv[0]);
        return 1;
    }

    snprintf(result_file, sizeof(result_file), "./%s/stats_file_GPU",result_dir);

    printf("Result file: %s\n", result_file);

    FILE *csv_file = fopen(result_file, "w");   
    if (csv_file == NULL) {
        perror("Error while creating statistics file");
        return 1;
    }
    fprintf(csv_file, "filename,H2D_time,Kernel_time,D2H_time\n"); 


    printf("%s starting...\n", argv[0]);

    // Set CUDA device
    int dev = 0;
    cudaDeviceProp deviceProp;
    CHECK(cudaGetDeviceProperties(&deviceProp, dev));
    printf("Using Device %d: %s\n", dev, deviceProp.name);
    CHECK(cudaSetDevice(dev));




    // Parse command line arguments
    int block_dim_x = 32;
    //int block_dim_y = atoi(argv[2]);

    dir = opendir(dirname);
    while((dd = readdir(dir)) != NULL){
        
        if(!strcmp(dd->d_name,".") || !strcmp(dd->d_name,"..")) continue;

        printf("Processing file: %s\n", dd->d_name);


        snprintf(path, sizeof(path), "%s/%s",dirname,dd->d_name);

        fptr = open(path, O_RDONLY);

        if(fptr < 0) {
            perror("File open not successful");
            exit(2);
        }

       

        
        struct stat info;
        if (stat(path, &info) != 0) perror("stat() error");
        else file_size = (long int) info.st_size;

        
        
        file_host = (char *)malloc(file_size * sizeof(char));
        gpuRef = (unsigned long long *)malloc(BIN_DIM*sizeof(unsigned long long));
        hostRef = (unsigned long long *)malloc(BIN_DIM*sizeof(unsigned long long));
 
        memset(gpuRef, 0, BIN_DIM * sizeof(unsigned long long));
        memset(hostRef, 0, BIN_DIM * sizeof(unsigned long long));

     

        index = 0;
        while ((nread = read(fptr, buffer, BUFFERSIZE)) > 0) {
            if (nread < 0) {
                perror("Error reading file");
                exit(3);
            }
            for (int i = 0; i < nread; i++) {
                file_host[index] = buffer[i];
                index++;
            }
        }

        close(fptr);


        // Allocate device memory
        printf("Memory allocated!");
        unsigned long long *d_bin;
        char *d_file;
        CHECK(cudaMalloc((void **)&d_bin, BIN_DIM*sizeof(unsigned long long)));
        CHECK(cudaMalloc((void **)&d_file, file_size * sizeof(char)));


        double tH2D_start = cpuSecond();
        CHECK(cudaMemcpy(d_file, file_host, file_size * sizeof(char), cudaMemcpyHostToDevice));
        double tH2D = cpuSecond() - tH2D_start;

        // Define grid and block dimensions 
        dim3 block, grid;
        block = dim3(block_dim_x);
        grid = dim3((file_size + block.x - 1) / block.x);





        //Lauch CPU function
        countCharOnCPU(file_host, hostRef,file_size); 


        // Launch kernel
        double tKernel_start = cpuSecond();
        countCharOnGPU<<<grid, block>>>(d_file, d_bin, file_size);
        CHECK(cudaDeviceSynchronize());
        double tKernel = cpuSecond() - tKernel_start;
    
        CHECK(cudaDeviceSynchronize());



        // Copy kernel result from device to host
        double tD2H_start = cpuSecond();
        CHECK(cudaMemcpy(gpuRef, d_bin, BIN_DIM*sizeof(unsigned long long), cudaMemcpyDeviceToHost));
        double tD2H = cpuSecond() - tD2H_start;

        fprintf(csv_file, "%s,%f,%f,%f\n", dd->d_name, tH2D, tKernel, tD2H);

        // Check result
        checkResult(hostRef, gpuRef, BIN_DIM);

        // Free device memory
        CHECK(cudaFree(d_bin));
        CHECK(cudaFree(d_file));


        // Free host memory
        free(file_host);
        free(gpuRef);
        free(hostRef);

        // Reset CUDA device
        CHECK(cudaDeviceReset());

        
        

    }
    closedir(dir);
    fclose(csv_file);

    // Reset CUDA device
    CHECK(cudaDeviceReset());
    return 0;
}













