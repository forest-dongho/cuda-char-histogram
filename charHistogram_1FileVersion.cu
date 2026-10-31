#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#define BIN_DIM 256
#define BUFFERSIZE 4906


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
void checkResult(int *hostRef, int *gpuRef, const int size) {
    double epsilon = 1.0E-8;
    bool match = 1;
    for (int i = 0; i < size; i++) {
        if ((hostRef[i] - gpuRef[i]) != 0) {
            match = 0;
            printf("Arrays do not match!\n");
            printf("host %d gpu %d at current %d\n", hostRef[i], gpuRef[i], i);
            
        }
    }
    if (match) printf("Arrays match !!!!\n\n");
}

// Kernel
__global__ void countCharOnGPU(char *file, int *bin, long int size){
    unsigned int ix = threadIdx.x + blockIdx.x * blockDim.x;
   

    if (ix < size){
        unsigned int idx = ix; // unsigned int idx = iy * W + ix;
        printf("thread %d processing character %c\n", ix, file[idx]);
        atomicAdd(&bin[(unsigned char)file[idx]], 1);
    } 
}

// Host function for char histogram
void countCharOnCPU(char *file, int *bin, long int size) {
  for (int i = 0; i < size; i++) {  
      bin[(unsigned char)file[i]]++;
  }
}



int main(int argc, char **argv) {
    printf("%s starting...\n", argv[0]);

    // Set CUDA device
    int dev = 0;
    cudaDeviceProp deviceProp;
    CHECK(cudaGetDeviceProperties(&deviceProp, dev));
    printf("Using Device %d: %s\n", dev, deviceProp.name);
    CHECK(cudaSetDevice(dev));

    // Check command line arguments
    if (argc != 4) {
        printf("Usage: %s <block_dim_x> <block_dim_y> <file_name>\n", argv[0]);
        return 1;
    }

    // Parse command line arguments
    int block_dim_x = atoi(argv[1]);
    int block_dim_y = atoi(argv[2]);
   
    long int file_size ;

    struct stat info;
    if (stat(argv[3], &info) != 0) perror("stat() error");
    else file_size = (long int) info.st_size;
    printf("File size: %ld\n", file_size);
    
   
    

    // Allocate host memory
    char *file_host;
    int *hostRef, *gpuRef;
    file_host = (char *)malloc(file_size * sizeof(char));
    hostRef = (int *)malloc(BIN_DIM*sizeof(int));
    gpuRef = (int *)malloc(BIN_DIM*sizeof(int));

    


    int nread;
  
   
    long int index = 0;
    char buffer[BUFFERSIZE];

    int fptr;

    
    fptr = open(argv[3], O_RDONLY);
    if (fptr < 0) {
        perror("File open not successful");
        exit(2);
    }


    while ((nread = read(fptr, buffer, BUFFERSIZE)) > 0) {
        for (int i = 0; i < nread; i++) {
            file_host[index] = buffer[i];
            index++;
        }
    }

    close(fptr);

    printf("File loaded successfully! size: %ld\n", file_size);


    double iStart;
    double iElaps;
    
    memset(hostRef, 0, BIN_DIM * sizeof(int));
    memset(gpuRef, 0, BIN_DIM * sizeof(int));

    // Add matrix on CPU
    iStart = cpuSecond();
    countCharOnCPU(file_host, hostRef,file_size); 
    iElaps = cpuSecond() - iStart;
    printf("countCharOnCPU elapsed %f s\n", iElaps);


    // Allocate device memory
    int *d_bin;
    char *d_file;
    CHECK(cudaMalloc((void **)&d_bin, BIN_DIM*sizeof(int)));
    CHECK(cudaMalloc((void **)&d_file, file_size * sizeof(char)));

    // Read file



    // Transfer data from host to device
    CHECK(cudaMemcpy(d_file, file_host, file_size * sizeof(char), cudaMemcpyHostToDevice));

    // Define grid and block dimensions 
    dim3 block, grid;
    block = dim3(block_dim_x, block_dim_y);
    grid = dim3((file_size + block.x - 1) / block.x);

    // Launch kernel
    iStart = cpuSecond();
    
    countCharOnGPU<<<grid, block>>>(d_file, d_bin, file_size);
   
    CHECK(cudaDeviceSynchronize());

    iElaps = cpuSecond() - iStart;
    printf("Kernel <<<(%d,%d), (%d,%d)>>> elapsed %f sec\n", grid.x, grid.y, block.x, block.y, iElaps);

    // Copy kernel result from device to host
    CHECK(cudaMemcpy(gpuRef, d_bin, BIN_DIM*sizeof(int), cudaMemcpyDeviceToHost));

    // Check result
    checkResult(hostRef, gpuRef, BIN_DIM);

    // Free device memory
    CHECK(cudaFree(d_bin));
    CHECK(cudaFree(d_file));


    // Free host memory
    free(file_host);
    free(hostRef);
    free(gpuRef);


    // Reset CUDA device
    CHECK(cudaDeviceReset());

    return 0;
}

