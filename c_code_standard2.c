#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <time.h>
#include <time.h> 
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#define BUFFERSIZE 4096


double cpuSecond() {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return ((double)ts.tv_sec + (double)ts.tv_nsec * 1.e-9);
}

int main() {
    DIR *dir;
    struct dirent *dd;

    int fd;
    int bin[256] = {0};
    char buffer[BUFFERSIZE];
    char result_file[512];
    char path[BUFFERSIZE];
    FILE *csv_file;
    int nread;
    long long numc;

    if (mkdir("./results", 0777) == 0) {
        printf("Directory created successfully!\n");
    } else {
        perror("Error creating directory");
    }

    char *dirname = "./datiUniformi"; 
    
    dir = opendir(dirname);
    while((dd = readdir(dir)) != NULL){
        
        if(!strcmp(dd->d_name,".") || !strcmp(dd->d_name,"..")) continue;

        printf("Found file %s !", dd->d_name);

        
        numc = 0;
        memset(bin, 0, sizeof(bin)); 

        snprintf(path, sizeof(path), "%s/%s",dirname,dd->d_name);

        fd = open(path, O_RDONLY);

        if(fd < 0) {
            perror("File open not successful");
            exit(2);
        }

        double iStart = cpuSecond();

        while ((nread = read(fd, buffer, BUFFERSIZE)) > 0) {
            for (int i = 0; i < nread; i++) {
                bin[(unsigned char)buffer[i]]++;
            }
            numc += nread;
        }

        if (nread < 0) {
            perror("Error reading file");
            close(fd);
            exit(3);
        }
        
        close(fd);

        double iElaps = cpuSecond() - iStart;

        snprintf(result_file, sizeof(result_file), "./results/stats_file_%s",dd->d_name);

           
        // --- SALVATAGGIO IN CSV (VIRTUALE / COLONNE) ---
        FILE *csv_file = fopen(result_file, "w");
        if (csv_file == NULL) {
            perror("Impossibile creare il file CSV");
        } else {
            // Intestazione delle colonne
            fprintf(csv_file, "Carattere,Codice_ASCII,Frequenza\n");

            // Righe di dati
            for (int i = 0; i < 256; i++) {
                if (bin[i] > 0) {
                    if (i >= 32 && i <= 126 && i != 34 && i != 44) { 
                        fprintf(csv_file, "'%c',%d,%d\n", i, i, bin[i]);
                    } else {
                        fprintf(csv_file, "Special/Control,%d,%d\n", i, bin[i]);
                    }
                }
            }

            // --- AGGIUNTA METADATI TEMPO ELABORAZIONE ---
            // Aggiungiamo due righe vuote e poi stampiamo la metrica delle performance
            fprintf(csv_file, "\n\n");
            fprintf(csv_file, "Metrica,Valore,\n");
            fprintf(csv_file, "Tempo impiegato (secondi),%f,\n", iElaps);

            fclose(csv_file);
            printf("\nDati salvati con successo in %s\n",result_file);
        }


       

    }

    
    closedir(dir);
    return 0;
}
