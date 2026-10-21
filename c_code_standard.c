#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <time.h>
#include <time.h> 
#include <dirent.h>


#define BUFFERSIZE 4906



double cpuSecond() {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return ((double)ts.tv_sec + (double)ts.tv_nsec * 1.e-9);
}

int main() {
    // Start timing right away
    double iStart = cpuSecond();
    int fptr;

    int bin[256] = {0};
    char buffer[BUFFERSIZE];

    char *filename = "./data/wiki_256MB.txt";
    fptr = open(filename, O_RDONLY);
    if (fptr < 0) {
        perror("File open not successful");
        exit(2);
    }

    int nread;
    long long numc = 0; 

    while ((nread = read(fptr, buffer, BUFFERSIZE)) > 0) {
        for (int i = 0; i < nread; i++) {
            bin[(unsigned char)buffer[i]]++;
        }
        numc += nread;
    }

    if (nread < 0) {
        perror("Error reading file");
        close(fptr);
        exit(3);
    }

    
    for (int i = 0; i < 256; i++) {
        if (bin[i] > 0) {
            if (i >= 32 && i <= 126) { 
                printf("'%c' (ASCII %d): %d\n", i, i, bin[i]);
            } else {
                
                printf("ASCII %d (Control Char): %d\n", i, bin[i]);
            }
        }
    }

    
    double iElaps = cpuSecond() - iStart;

    printf("\nCount characters time elapsed %f sec\n", iElaps);
    printf("The number of characters read is %lld.\n", numc);

    close(fptr);
    return 0;
}
