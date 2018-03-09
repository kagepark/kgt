#!/bin/bash -l
#SBATCH --partition=test.q 
#SBATCH --job-name=ppjob  
#SBATCH -N 3
#SBATCH --chdir=/global/work/pingpong
#SBATCH --output=ppjob.%j.out
#SBATCH --error=ppjob.%j.err
#
###############################################################
## Module ##
# . /etc/profile.d/modules.sh
module load mpi
[ -d /global/work/pingpong ] || mkdir -p /global/work/pingpong
cat << EOF > /global/work/pingpong/pingpong.c
#include <stdio.h>
#include <stdlib.h>
#include "mpi.h"
#include <unistd.h>
#include <time.h>
#include <sys/times.h>

#define TRUE    1
#define FALSE   0

#define MAX_QSC_NAME 64

#ifdef PRE_ALLOC
    static char buf1[10000000], buf2[10000000];
#endif

int main(int argc, char *argv[])
{
    MPI_Status     status;               /* MPI status                          */
    int            mpierr;               /* MPI function return code            */
    int            rank;                 /* Process rank within MPI_COMM_WORLD  */
    int            nproc;                /* Total number of MPI processes       */
    int            tag0=41;              /* MPI message tag                     */
    int            tag1=42;              /* MPI message tag                     */
    int            warmup=0;             /* MPI warmup loops                    */
    char           process_name[MPI_MAX_PROCESSOR_NAME + 1];
    char           partner_name[MPI_MAX_PROCESSOR_NAME + 1];
    char           qsc_empty[] = {"???????"};
    int            n_bytes = 4194304 * 2, maxBytes;
    int            n_loops = 50, d_loops;
    unsigned char* send_buff;
    unsigned char* recv_buff;
    int            useClock = TRUE;
    int            i,j,k,count,mismatch;
    double         et1,et2,mbs;
    et1 = 0.0;
    et2 = 0.0;

    /* GET INPUT PARAMETERS: ONLY THE LAST TWO ARE MINE */
    if (argc >= 3) {
         n_loops = atoi(argv[argc-2]);
         n_bytes = atol(argv[argc-1]);
    }
    maxBytes = 2;
    i = 0;
    while (maxBytes < n_bytes) {
        maxBytes *=2;
        ++i;
    }

    n_bytes = maxBytes;
    d_loops = n_loops;
    n_loops *= i;
#ifdef PRE_ALLOC
    if (n_bytes > 10000000) {
        fprintf(stderr, "pingpong only works for sizes <= 10000000\n");
        exit;
    }
    send_buff = &buf1[0];
    recv_buff = &buf2[0];
#else
    send_buff = (unsigned char *) valloc(n_bytes);
    recv_buff = (unsigned char *) valloc(n_bytes);
#endif
    mpierr = MPI_Init(&argc, &argv);
    if (mpierr != MPI_SUCCESS) {
        fprintf(stderr, "MPI Error %d (MPI_Init)\n",mpierr);
        fflush(stderr);
        MPI_Abort(MPI_COMM_WORLD, -1);
    }

    mpierr = MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    if (mpierr != MPI_SUCCESS || rank < 0) {
        fprintf(stderr, "MPI Error %d (MPI_Comm_rank)\n",mpierr);
        fflush(stderr);
        MPI_Abort(MPI_COMM_WORLD, -1);
    }

    mpierr = MPI_Comm_size(MPI_COMM_WORLD, &nproc);
    if (mpierr != MPI_SUCCESS || nproc < 1 || nproc <= rank) {
        fprintf(stderr, "MPI Error %d (MPI_Comm_size) [%d]\n",mpierr, rank);
        fflush(stderr);
        MPI_Abort(MPI_COMM_WORLD, -1);
    }

    mpierr = MPI_Get_processor_name(process_name, &count);
    if (mpierr != MPI_SUCCESS) {
        fprintf(stderr,"MPI Error %d (MPI_Get_processor_name) [%d]\n", mpierr, rank);
        sprintf(process_name, qsc_empty);
    }

    n_bytes = 8;
    n_bytes = maxBytes;
    n_loops = d_loops;
    while (n_bytes <= maxBytes) {

    for ( i=0; i<n_bytes; i++ ) {
        send_buff[i] = i%128;
    }

    for ( i=0; i < nproc; i++) {
    //i = 0;
        for ( j = i + 1; j < nproc; j++) {
        //for ( j = 0; j < nproc; j++) {
            //if (j == i)
            //  continue;
            if (rank == j) {
                mpierr = MPI_Send(process_name, MPI_MAX_PROCESSOR_NAME + 1,
                                  MPI_CHAR, i, tag0, MPI_COMM_WORLD);
                if (mpierr != MPI_SUCCESS) {
                    fprintf(stderr,"MPI Error %d (MPI_Recv) %s [%d]\n",
                                mpierr,process_name,i);
                    fflush(stderr);
                        MPI_Abort(MPI_COMM_WORLD, -1);
                }
                for (k=0; k < n_bytes; k++)
                    recv_buff[k] = 0x80;
            }
            if ( rank == i ) {
                mpierr = MPI_Recv(partner_name, MPI_MAX_PROCESSOR_NAME + 1,
                                  MPI_BYTE, j, tag0, MPI_COMM_WORLD, &status);
                if (mpierr != MPI_SUCCESS) {
                    fprintf(stderr,"MPI Error %d (MPI_Send) %s [%d]\n",
                            mpierr,process_name,rank);
                    fflush(stderr);
                    MPI_Abort(MPI_COMM_WORLD, -1);
                }
            }

            MPI_Barrier(MPI_COMM_WORLD);

            for ( k=0; k<n_loops+warmup; k++ ) {
                if ( rank == i ) {
                    if (k == warmup) {
                        if (useClock)
                            et1 = ((float) clock()) / ((float) CLOCKS_PER_SEC);
                        else
                            et1 = MPI_Wtime();
                    }
                    mpierr = MPI_Send(send_buff, n_bytes, MPI_BYTE, j, tag1,
                                       MPI_COMM_WORLD);
                    if (mpierr != MPI_SUCCESS) {
                        fprintf(stderr,"MPI Error %d (MPI_Send) %s [%d]\n",
                                            mpierr,process_name,rank);
                        fflush(stderr);
                        MPI_Abort(MPI_COMM_WORLD, -1);
                    }

                    mpierr = MPI_Recv(recv_buff, n_bytes, MPI_BYTE, j,
                                tag1, MPI_COMM_WORLD, &status);
                    if (mpierr != MPI_SUCCESS) {
                        fprintf(stderr,"MPI Error %d (MPI_Recv) %s [%d]\n",
                             mpierr,process_name,i);
                        fflush(stderr);
                        MPI_Abort(MPI_COMM_WORLD, -1);
                    }
                    if (k == n_loops+warmup-1) {
                        if (useClock)
                            et2 = ((float) clock()) / ((float) CLOCKS_PER_SEC);
                        else
                            et2 = MPI_Wtime();
                    }
                }
                if ( rank == j ) {
                    mpierr = MPI_Recv(recv_buff, n_bytes, MPI_BYTE, i,
                                   tag1, MPI_COMM_WORLD, &status);
                    if (mpierr != MPI_SUCCESS) {
                        fprintf(stderr,"MPI Error %d (MPI_Recv) %s [%d]\n",
                                 mpierr,process_name,i);
                        fflush(stderr);
                        MPI_Abort(MPI_COMM_WORLD, -1);
                    }

                    mpierr = MPI_Send(recv_buff, n_bytes, MPI_BYTE, i, tag1,
                                       MPI_COMM_WORLD);
                    if (mpierr != MPI_SUCCESS) {
                        fprintf(stderr,"MPI Error %d (MPI_Send) %s [%d]\n",
                            mpierr,process_name,rank);
                        fflush(stderr);
                        MPI_Abort(MPI_COMM_WORLD, -1);
                    }
                }
            }
            if ( rank == i ) {
                if (i == 0 && j == 1)
                    printf("\nn_loops=%d  n_bytes=%d useClock=%d\n",
                        n_loops, n_bytes,useClock);

                mbs = ((double)2*n_loops*n_bytes)/(1000000.0*(et2-et1));
                printf("   %s <<=====>> %s        %9.0f MBS    %9.1f Sec.\n",
                                    process_name,partner_name,mbs,et2-et1);
                fflush(stdout);
                mismatch = 0;
                for (k=0; k < n_bytes; k++)
                    if ( recv_buff[k] != k%128 ) mismatch++;
                if ( mismatch ) printf("                                                                  WARNING! %d data mismatches rank=%d\n",mismatch,rank);
                    fflush(stdout);
            }
        }
    }

    n_bytes *= 2;
    n_loops -= d_loops;
    }

    mpierr = MPI_Finalize();
    if (mpierr != MPI_SUCCESS) {
        fprintf(stderr,"MPI Error %d (MPI_Finalize) %s [%d]\n",mpierr,process_name,rank);
        fflush(stderr);
        MPI_Abort(MPI_COMM_WORLD, -1);
    }

    return 0;
}
EOF
mpicc /global/work/pingpong/pingpong.c -o /global/work/pingpong/pingpong
sleep 2

srun --nodes=${SLURM_NNODES} bash -c 'hostname -s' | sed "s/$/-ib0/g"  > /tmp/slurm.node
sleep 2
mpirun -np $(cat /tmp/slurm.node | wc -l) -machinefile /tmp/slurm.node -iface=ib0 ./pingpong
