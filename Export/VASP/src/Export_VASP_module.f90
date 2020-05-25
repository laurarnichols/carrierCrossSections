module wfcExportVASPMod

  USE wrappers,      ONLY : f_mkdir_safe
  USE pwcom

  USE io_global, ONLY : ionode, ionode_id
  USE io_files,  ONLY : prefix, outdir
  USE ions_base, ONLY : ntype => nsp
  USE iotk_module
  USE mp_global, ONLY : mp_startup
  USE mp_pools,  ONLY : intra_pool_comm, me_pool, my_pool_id, nproc_pool, root_pool
  USE parallel_include
  !USE mp_pools
  !USE mp_world,  ONLY: world_comm
  USE mp_world
  USE mp,        ONLY: mp_bcast, mp_sum, mp_max, mp_get
  USE mp_wave, ONLY : mergewf
  USE environment,   ONLY : environment_start

  implicit none

  integer, parameter :: stdout = 6
    !! Standard output unit

  CHARACTER(LEN=256), EXTERNAL :: trimcheck
  
  INTEGER :: ik, i
  integer :: ios
    !! Error for input/output
  integer :: npool
    !! Number of pools for kpoint parallelization
  
  real(kind = dp), parameter :: ryToHartree = 0.5_dp
  
  character(len=256) :: exportDir
    !! Directory to be used for export
  character(len=256) :: mainOutputFile
    !! Main output file

  NAMELIST /inputParams/ prefix, outdir, exportDir


  contains

!----------------------------------------------------------------------------
  subroutine initialize()
    !! Set the default values for input variables
    !!
    !! <h2>Walkthrough</h2>
    
    implicit none

    prefix = ''
    outdir = './'
    exportDir = './Export'

  end subroutine initialize

!----------------------------------------------------------------------------
  subroutine exitError(calledFrom, message, ierr)
    !! Output error message and abort if ierr > 0
    !!
    !! Can ensure that error will cause abort by
    !! passing abs(ierr)
    !!
    !! <h2>Walkthrough</h2>
    
    implicit none

    integer, intent(in) :: ierr
      !! Error

    character(len=*), intent(in) :: calledFrom
      !! Place where this subroutine was called from
    character(len=*), intent(in) :: message
      !! Error message

    integer :: id
      !! ID of this process
    integer :: mpierr
      !! Error output from MPI

    character(len=6) :: cerr
      !! String version of error


    if ( ierr <= 0 ) return
      !! * Do nothing if the error is less than or equal to zero

    write( cerr, fmt = '(I6)' ) ierr
      !! * Write ierr to a string
    write(unit=*, fmt = '(/,1X,78("%"))' )
      !! * Output a dividing line
    write(unit=*, fmt = '(5X,"Error in ",A," (",A,"):")' ) trim(calledFrom), trim(adjustl(cerr))
      !! * Output where the error occurred and the error
    write(unit=*, fmt = '(5X,A)' ) TRIM(message)
      !! * Output the error message
    write(unit=*, fmt = '(1X,78("%"),/)' )
      !! * Output a dividing line

    write( *, '("     stopping ...")' )
  
    call flush( stdout )

#if defined (__MPI)
  
    id = 0
  
    !> * For MPI, get the id of this process and abort
    call MPI_COMM_RANK( MPI_COMM_WORLD, id, mpierr )
    call MPI_ABORT( MPI_COMM_WORLD, mpierr )
    call MPI_FINALIZE( mpierr )

#endif

    stop 2

    return

  end subroutine exitError

!----------------------------------------------------------------------------
  subroutine readInputFiles()
    implicit none


    return
  end subroutine readInputFiles

!----------------------------------------------------------------------------
  subroutine distributeKpointsInPools()
    !!
    !!
    !! <h2>Walkthrough</h2>

    implicit none

    integer :: nkl
      !! Number of kpoints in each pool


    if( nkstot > 0 ) then
      !! @todo Figure out where `nkstot` comes from @endtodo

      IF( ( nproc_pool > nproc ) .or. ( mod( nproc, nproc_pool ) /= 0 ) ) &
        CALL exitError( ' write_export ',' nproc_pool ', 1 )
        !! @todo Figure out where `nproc_pool` comes from @endtodo
        !! @todo Figure out where `nproc` comes from @endtodo

      npool = nproc / nproc_pool
        !!  * Calculate number of pools

      nkl = nkstot / npool
        !!  * Calculate k points per pool
        !! @todo Figure out where `nkl` should be defined @endtodo
        !! @todo Figure out where `nkstot` comes from @endtodo

      nkr = nkstot - nkl * npool 
        !! * Calculate the remainder
        !! @todo Figure out where `nkr` should be defined @endtodo

      IF( my_pool_id < nkr ) nkl = nkl + 1
        !! * Assign the remainder to the first `nkr` pools

      !>  * Calculate the index of the first k point in this pool
      iks = nkl * my_pool_id + 1
        !! @todo Figure out where `iks` should be defined @endtodo
      IF( my_pool_id >= nkr ) iks = iks + nkr

      ike = iks + nkl - 1
        !!  * Calculate the index of the last k point in this pool
        !! @todo Figure out where `ike` should be defined @endtodo

    endif

    return
  end subroutine distributeKpointsInPools

!----------------------------------------------------------------------------
! ..  This subroutine write wavefunctions to the disk
! .. Where:
! iuni    = Restart file I/O fortran unit
!
    SUBROUTINE write_restart_wfc(iuni, exportDir, &
      ik, nk, ispin, nspin, scal, wf0, t0, wfm, tm, ngw, gamma_only, nbnd, igl, ngwl )
!
!
      IMPLICIT NONE
!
      INTEGER, INTENT(in) :: iuni
      character(len = 256), intent(in) :: exportDir
      INTEGER, INTENT(in) :: ik, nk, ispin, nspin
      COMPLEX(DP), INTENT(in) :: wf0(:,:)
      COMPLEX(DP), INTENT(in) :: wfm(:,:)
      INTEGER, INTENT(in) :: ngw   !
      LOGICAL, INTENT(in) :: gamma_only
      INTEGER, INTENT(in) :: nbnd
      INTEGER, INTENT(in) :: ngwl
      INTEGER, INTENT(in) :: igl(:)
      REAL(DP), INTENT(in) :: scal
      LOGICAL, INTENT(in) :: t0, tm

      INTEGER :: i, j, ierr, idum = 0
      INTEGER :: nkl, nkr, nkbl, iks, ike, nkt, ikt, igwx, ig
      INTEGER :: npool, ipmask( nproc ), ipsour
      COMPLEX(DP), ALLOCATABLE :: wtmp(:)
      INTEGER, ALLOCATABLE :: igltot(:)

      CHARACTER(len=20) :: section_name = 'wfc'

      LOGICAL :: twrite = .true.

      INTEGER :: ierr_iotk
      CHARACTER(len=iotk_attlenx) :: attr

!
! ... Subroutine Body
!

        ! set working variables for k point index (ikt) and k points number (nkt)
        ikt = ik
        nkt = nk

        !  find out the number of pools
        npool = nproc / nproc_pool

        !  find out number of k points blocks
        nkbl = nkt

        !  k points per pool
        nkl = nkbl / npool

        !  find out the reminder
        nkr = nkt - nkl * npool

        !  Assign the reminder to the first nkr pools
        IF( my_pool_id < nkr ) nkl = nkl + 1

        !  find out the index of the first k point in this pool
        iks = nkl * my_pool_id + 1
        IF( my_pool_id >= nkr ) iks = iks + nkr 

        !  find out the index of the last k point in this pool
        ike = iks + nkl - 1

        ipmask = 0
        ipsour = ionode_id

        !  find out the index of the processor which collect the data in the pool of ik
        IF( npool > 1 ) THEN
          IF( ( ikt >= iks ) .and. ( ikt <= ike ) ) THEN
            IF( me_pool == root_pool ) ipmask( mpime + 1 ) = 1
          ENDIF
          CALL mp_sum( ipmask, world_comm )
          DO i = 1, nproc
            IF( ipmask(i) == 1 ) ipsour = ( i - 1 )
          ENDDO
        ENDIF

        igwx = 0
        ierr = 0
        IF( ( ikt >= iks ) .and. ( ikt <= ike ) ) THEN
          IF( ngwl > size( igl ) ) THEN
            ierr = 1
          ELSE
            igwx = maxval( igl(1:ngwl) )
          ENDIF
        ENDIF

        ! get the maximum index within the pool
        !
        CALL mp_max( igwx, intra_pool_comm )

        ! now notify all procs if an error has been found
        !
        CALL mp_max( ierr, world_comm )

        IF( ierr > 0 ) &
          CALL exitError(' write_restart_wfc ',' wrong size ngl ', ierr )

        IF( ipsour /= ionode_id ) THEN
          CALL mp_get( igwx, igwx, mpime, ionode_id, ipsour, 1, world_comm )
        ENDIF

        ALLOCATE( wtmp( max(igwx,1) ) )
        wtmp = cmplx(0.0_dp, 0.0_dp, kind=dp)

        DO j = 1, nbnd
          IF( t0 ) THEN
            IF( npool > 1 ) THEN
              IF( ( ikt >= iks ) .and. ( ikt <= ike ) ) THEN
                CALL mergewf(wf0(:,j), wtmp, ngwl, igl, me_pool, &
                             nproc_pool, root_pool, intra_pool_comm)
              ENDIF
              IF( ipsour /= ionode_id ) THEN
                CALL mp_get( wtmp, wtmp, mpime, ionode_id, ipsour, j, world_comm )
              ENDIF
            ELSE
              CALL mergewf(wf0(:,j), wtmp, ngwl, igl, mpime, nproc, &
                           ionode_id, world_comm )
            ENDIF

            IF( ionode ) THEN
              do ig = 1, igwx
                write(iuni, '(2ES24.15E3)') wtmp(ig)
              enddo
              !
!              do j = 1, nbnd
!                do i = 1, igwx ! ngk_g(ik)
!                  write(74,'(2ES24.15E3)') wf0(i,j) ! wf0 is the local array for evc(i,j)
!                enddo
!              enddo
              !
            ENDIF
          ELSE
          ENDIF
        ENDDO

!        DO j = 1, nbnd
!          IF( tm ) THEN
!            IF( npool > 1 ) THEN
!              IF( ( ikt >= iks ) .and. ( ikt <= ike ) ) THEN
!                CALL mergewf(wfm(:,j), wtmp, ngwl, igl, me_pool, &
!                             nproc_pool, root_pool, intra_pool_comm)
!              ENDIF
!              IF( ipsour /= ionode_id ) THEN
!                CALL mp_get( wtmp, wtmp, mpime, ionode_id, ipsour, j, world_comm )
!              ENDIF
!            ELSE
!              CALL mergewf(wfm(:,j), wtmp, ngwl, igl, mpime, nproc, ionode_id, world_comm )
!            ENDIF
!            IF( ionode ) THEN
!              CALL iotk_write_dat(iuni,"Wfcm"//iotk_index(j),wtmp(1:igwx))
!            ENDIF
!          ELSE
!          ENDIF
!        ENDDO
        IF(ionode) then
          close(iuni)
          !CALL iotk_write_end  (iuni,"Kpoint"//iotk_index(ik))
        endif
      
        DEALLOCATE( wtmp )

      RETURN
    END SUBROUTINE

  SUBROUTINE write_export (mainOutputFile, exportDir)
    !-----------------------------------------------------------------------
    !
    USE iotk_module


    USE kinds,          ONLY : DP
    USE pwcom
    USE start_k,        ONLY : nk1, nk2, nk3, k1, k2, k3
    USE control_flags,  ONLY : gamma_only
    USE global_version, ONLY : version_number
    USE becmod,         ONLY : bec_type, becp, calbec, &
                             allocate_bec_type, deallocate_bec_type

    USE uspp,          ONLY : nkb, vkb
    USE wavefunctions_module,  ONLY : evc
    USE io_files,       ONLY : outdir, prefix, iunwfc, nwordwfc
    USE io_files,       ONLY : psfile
    USE io_global,      ONLY : ionode, stdout
    USE ions_base,      ONLY : atm, nat, ityp, tau, nsp
    USE mp_pools,       ONLY : my_pool_id, intra_pool_comm, inter_pool_comm, &
                             nproc_pool
    USE mp,             ONLY : mp_sum, mp_max
    USE mp_world,       ONLY : world_comm, nproc, mpime
  
    USE upf_module,     ONLY : read_upf
  
    USE pseudo_types, ONLY : pseudo_upf
    USE radial_grids, ONLY : radial_grid_type
    
    USE wvfct,         ONLY : wg
  
    USE paw_variables,        ONLY : okpaw, ddd_paw, total_core_energy, only_paw
    USE paw_onecenter,        ONLY : PAW_potential
    USE paw_symmetry,         ONLY : PAW_symmetrize_ddd
    USE uspp_param,           ONLY : nh, nhm ! used for PAW
    USE uspp,                 ONLY : qq_so, dvan_so, qq, dvan
    USE scf,                  ONLY : rho

    IMPLICIT NONE
  
    CHARACTER(5), PARAMETER :: fmt_name="QEXPT"
    CHARACTER(5), PARAMETER :: fmt_version="1.1.0"

    CHARACTER(256), INTENT(in) :: mainOutputFile, exportDir

    INTEGER :: i, j, k, ig, ik, ibnd, na, ngg,ig_, ierr
    INTEGER, ALLOCATABLE :: kisort(:)
    real(DP) :: xyz(3), tmp(3)
    INTEGER :: npool, nkl, nkr, npwx_g, im, ink, inb, ms
    INTEGER :: ike, iks, npw_g, ispin, local_pw
    INTEGER, ALLOCATABLE :: ngk_g( : )
    INTEGER, ALLOCATABLE :: itmp_g( :, : )
    real(DP),ALLOCATABLE :: rtmp_g( :, : )
    real(DP),ALLOCATABLE :: rtmp_gg( : )
    INTEGER, ALLOCATABLE :: itmp1( : )
    INTEGER, ALLOCATABLE :: igwk( :, : )
    INTEGER, ALLOCATABLE :: l2g_new( : )
    INTEGER, ALLOCATABLE :: igk_l2g( :, : )
  


  
    character(len = 300) :: text
  

    real(DP) :: wfc_scal
    LOGICAL :: twf0, twfm, file_exists
    CHARACTER(iotk_attlenx) :: attr
    TYPE(pseudo_upf) :: upf       ! the pseudo data
    TYPE(radial_grid_type) :: grid

    integer, allocatable :: nnTyp(:), groundState(:)

    ! find out the global number of G vectors: ngm_g
    ngm_g = ngm
    CALL mp_sum( ngm_g , intra_pool_comm )


    !  Open file PP_FILE

    IF( ionode ) THEN
    
      WRITE(stdout,*) "Opening file "//trim(mainOutputFile)
    
      open(50, file=trim(mainOutputFile))

      WRITE(stdout,*) "Reconstructing the main grid"
    
    endif

    ! collect all G vectors across processors within the pools
    ! and compute their modules
  
    ALLOCATE( itmp_g( 3, ngm_g ) )
    ALLOCATE( rtmp_g( 3, ngm_g ) )
    ALLOCATE( rtmp_gg( ngm_g ) )

    itmp_g = 0
    DO  ig = 1, ngm
      itmp_g( 1, ig_l2g( ig ) ) = mill(1,ig )
      itmp_g( 2, ig_l2g( ig ) ) = mill(2,ig )
      itmp_g( 3, ig_l2g( ig ) ) = mill(3,ig )
    ENDDO
  
    CALL mp_sum( itmp_g , intra_pool_comm )
  
    ! here we are in crystal units
    rtmp_g(1:3,1:ngm_g) = REAL( itmp_g(1:3,1:ngm_g) )
  
    ! go to cartesian units (tpiba)
    CALL cryst_to_cart( ngm_g, rtmp_g, bg , 1 )
  
    ! compute squared moduli
    DO  ig = 1, ngm_g
      rtmp_gg(ig) = rtmp_g(1,ig)**2 + rtmp_g(2,ig)**2 + rtmp_g(3,ig)**2
    ENDDO
    DEALLOCATE( rtmp_g )

    ! build the G+k array indexes
    ALLOCATE ( igk_l2g ( npwx, nks ) )
    ALLOCATE ( kisort( npwx ) )
    DO ik = 1, nks
      kisort = 0
      npw = npwx
      CALL gk_sort (xk (1, ik+iks-1), ngm, g, ecutwfc / tpiba2, npw, kisort(1), g2kin)

      ! mapping between local and global G vector index, for this kpoint
     
      DO ig = 1, npw
        
        igk_l2g(ig,ik) = ig_l2g( kisort(ig) )
        
      ENDDO
     
      igk_l2g( npw+1 : npwx, ik ) = 0
     
      ngk (ik) = npw
    ENDDO
    DEALLOCATE (kisort)

    ! compute the global number of G+k vectors for each k point
    ALLOCATE( ngk_g( nkstot ) )
    ngk_g = 0
    ngk_g( iks:ike ) = ngk( 1:nks )
    CALL mp_sum( ngk_g, world_comm )

    ! compute the Maximum G vector index among all G+k and processors
    npw_g = maxval( igk_l2g(:,:) )
    CALL mp_max( npw_g, world_comm )

    ! compute the Maximum number of G vector among all k points
    npwx_g = maxval( ngk_g( 1:nkstot ) )

    IF( ionode ) THEN
    

      write(50, '("# Cell volume (a.u.)^3. Format: ''(ES24.15E3)''")')
      write(50, '(ES24.15E3)' ) omega
    
      write(50, '("# Number of K-points. Format: ''(i10)''")')
      write(50, '(i10)') nkstot
    
      write(50, '("# ik, groundState, ngk_g(ik), wk(ik), xk(1:3,ik). Format: ''(3i10,4ES24.15E3)''")')
    
      allocate ( groundState(nkstot) )

      groundState(:) = 0
      DO ik=1,nkstot
        do ibnd = 1, nbnd
          if ( wg(ibnd,ik)/wk(ik) < 0.5_dp ) then
          !if (et(ibnd,ik) > ef) then
            groundState(ik) = ibnd - 1
            goto 10
          endif
        enddo
10      continue
      enddo
    
    endif
  
    ALLOCATE( igwk( npwx_g, nkstot ) )
  
    DO ik = 1, nkstot
      igwk(:,ik) = 0
    
      ALLOCATE( itmp1( npw_g ), STAT= ierr )
      IF ( ierr/=0 ) CALL exitError('pw_export','allocating itmp1', abs(ierr) )
      itmp1 = 0
    
      IF( ik >= iks .and. ik <= ike ) THEN
        DO  ig = 1, ngk( ik-iks+1 )
          itmp1( igk_l2g( ig, ik-iks+1 ) ) = igk_l2g( ig, ik-iks+1 )
        ENDDO
      ENDIF
    
      CALL mp_sum( itmp1, world_comm )
    
      ngg = 0
      DO  ig = 1, npw_g
        IF( itmp1( ig ) == ig ) THEN
          ngg = ngg + 1
          igwk( ngg , ik) = ig
        ENDIF
      ENDDO
      IF( ngg /= ngk_g( ik ) ) THEN
        if ( ionode ) WRITE(50, *) ' ik, ngg, ngk_g = ', ik, ngg, ngk_g( ik )
      ENDIF
    
      DEALLOCATE( itmp1 )
    
      if ( ionode ) write(50, '(3i10,4ES24.15E3)') ik, groundState(ik), ngk_g(ik), wk(ik), xk(1:3,ik)
    
    ENDDO
  
    if ( ionode ) then
    
      write(50, '("# Number of G-vectors. Format: ''(i10)''")')
      write(50, '(i10)') ngm_g
    
      write(50, '("# Number of PW-vectors. Format: ''(i10)''")')
      write(50, '(i10)') npw_g
    
      write(50, '("# Number of min - max values of fft grid in x, y and z axis. Format: ''(6i10)''")')
      write(50, '(6i10)') minval(itmp_g(1,1:ngm_g)), maxval(itmp_g(1,1:ngm_g)), &
                          minval(itmp_g(2,1:ngm_g)), maxval(itmp_g(2,1:ngm_g)), &
                          minval(itmp_g(3,1:ngm_g)), maxval(itmp_g(3,1:ngm_g))
    
      write(50, '("# Cell (a.u.). Format: ''(a5, 3ES24.15E3)''")')
      write(50, '("# a1 ",3ES24.15E3)') at(:,1)*alat
      write(50, '("# a2 ",3ES24.15E3)') at(:,2)*alat
      write(50, '("# a3 ",3ES24.15E3)') at(:,3)*alat
    
      write(50, '("# Reciprocal cell (a.u.). Format: ''(a5, 3ES24.15E3)''")')
      write(50, '("# b1 ",3ES24.15E3)') bg(:,1)*tpiba
      write(50, '("# b2 ",3ES24.15E3)') bg(:,2)*tpiba
      write(50, '("# b3 ",3ES24.15E3)') bg(:,3)*tpiba
    
      write(50, '("# Number of Atoms. Format: ''(i10)''")')
      write(50, '(i10)') nat
    
      write(50, '("# Number of Types. Format: ''(i10)''")')
      write(50, '(i10)') nsp
    
      write(50, '("# Atoms type, position(1:3) (a.u.). Format: ''(i10,3ES24.15E3)''")')
      DO i = 1, nat
        xyz = tau(:,i)
        write(50,'(i10,3ES24.15E3)') ityp(i), tau(:,i)*alat
      ENDDO
    
      write(50, '("# Number of Bands. Format: ''(i10)''")')
      write(50, '(i10)') nbnd
    
      DO ik = 1, nkstot
      
        open(72, file=trim(exportDir)//"/grid"//iotk_index(ik))
        write(72, '("# Wave function G-vectors grid")')
        write(72, '("# G-vector index, G-vector(1:3) miller indices. Format: ''(4i10)''")')
      
        do ink = 1, ngk_g(ik)
          write(72, '(4i10)') igwk(ink,ik), itmp_g(1:3,igwk(ink,ik))
        enddo
      
        close(72)
      
      ENDDO
    
      open(72, file=trim(exportDir)//"/mgrid")
      write(72, '("# Full G-vectors grid")')
      write(72, '("# G-vector index, G-vector(1:3) miller indices. Format: ''(4i10)''")')
    
      do ink = 1, ngm_g
        write(72, '(4i10)') ink, itmp_g(1:3,ink)
      enddo
    
      close(72)

      write(50, '("# Spin. Format: ''(i10)''")')
      write(50, '(i10)') nspin
    
      allocate( nnTyp(nsp) )
      nnTyp = 0
      do i = 1, nat
        nnTyp(ityp(i)) = nnTyp(ityp(i)) + 1
      enddo

      DO i = 1, nsp
      
        call read_upf(upf, grid, ierr, 71, trim(outdir)//'/'//trim(prefix)//'.save/'//trim(psfile(i)))
      
        if (  upf%typ == 'PAW' ) then
        
          write(stdout, *) ' PAW type pseudopotential found !'
        
          write(50, '("# Element")')
          write(50, *) trim(atm(i))
          write(50, '("# Number of Atoms of this type. Format: ''(i10)''")')
          write(50, '(i10)') nnTyp(i)
          write(50, '("# Number of projectors. Format: ''(i10)''")')
          write(50, '(i10)') upf%nbeta              ! number of projectors
        
          write(50, '("# Angular momentum, index of the projectors. Format: ''(2i10)''")')
          ms = 0
          do inb = 1, upf%nbeta
            write(50, '(2i10)') upf%lll(inb), inb
            ms = ms + 2*upf%lll(inb) + 1
          enddo
        
          write(50, '("# Number of channels. Format: ''(i10)''")')
          write(50, '(i10)') ms
        
          write(50, '("# Number of radial mesh points. Format: ''(2i10)''")')
          write(50, '(2i10)') upf%mesh, upf%kkbeta ! number of points in the radial mesh, number of point inside the aug sphere
        
          write(50, '("# Radial grid, Integratable grid. Format: ''(2ES24.15E3)''")')
          do im = 1, upf%mesh
            write(50, '(2ES24.15E3)') upf%r(im), upf%rab(im) ! r(mesh) radial grid, rab(mesh) dr(x)/dx (x=linear grid)
          enddo
        
          write(50, '("# AE, PS radial wfc for each beta function. Format: ''(2ES24.15E3)''")')
          if ( upf%has_wfc ) then   ! if true, UPF contain AE and PS wfc for each beta
            do inb = 1, upf%nbeta
              do im = 1, upf%mesh
                write(50, '(2ES24.15E3)') upf%aewfc(im, inb), upf%pswfc(im, inb)
                                          ! wfc(mesh,nbeta) AE wfc, wfc(mesh,nbeta) PS wfc
              enddo
            enddo
          else
            write(50, *) 'UPF does not contain AE and PS wfcs!!'
            stop
          endif
        
        endif
      
      enddo
    
    ENDIF
  
    DEALLOCATE( rtmp_gg )

#ifdef __MPI
  CALL poolrecover (et, nbnd, nkstot, nks)
#endif


    WRITE(stdout,*) "Writing Eigenvalues"

    IF( ionode ) THEN
    
      write(50, '("# Fermi Energy (Hartree). Format: ''(ES24.15E3)''")')
      write(50, '(ES24.15E3)') ef*ryToHartree
      flush(50)
    
      DO ik = 1, nkstot
      
        ispin = isk( ik )
      
        open(72, file=trim(exportDir)//"/eigenvalues"//iotk_index(ik))
      
        write(72, '("# Spin : ",i10, " Format: ''(a9, i10)''")') ispin
        write(72, '("# Eigenvalues (Hartree), band occupation number. Format: ''(2ES24.15E3)''")')
      
        do ibnd = 1, nbnd
          if ( wk(ik) == 0.D0 ) then
              write(72, '(2ES24.15E3)') et(ibnd,ik)*ryToHartree, wg(ibnd,ik)
           else
            write(72, '(2ES24.15E3)') et(ibnd,ik)*ryToHartree, wg(ibnd,ik)/wk(ik)
          endif
        enddo
      
        close(72)
      
      ENDDO
    
    endif
  
    if ( ionode ) WRITE(stdout,*) "Writing Wavefunctions"
  
    wfc_scal = 1.0d0
    twf0 = .true.
    twfm = .false.
  
    IF ( nkb > 0 ) THEN
    
      CALL init_us_1
      CALL init_at_1
    
      CALL allocate_bec_type (nkb,nbnd, becp)
    
      DO ik = 1, nkstot
      
        local_pw = 0
        IF ( (ik >= iks) .and. (ik <= ike) ) THEN
          CALL gk_sort (xk (1, ik+iks-1), ngm, g, ecutwfc / tpiba2, npw, igk, g2kin)
          CALL davcio (evc, nwordwfc, iunwfc, (ik-iks+1), - 1)

          CALL init_us_2(npw, igk, xk(1, ik), vkb)
          local_pw = ngk(ik-iks+1)

          IF ( gamma_only ) THEN
            CALL calbec ( ngk_g(ik), vkb, evc, becp )
            WRITE(0,*) 'Gamma only PW_EXPORT not yet tested'
          ELSE
            CALL calbec ( npw, vkb, evc, becp )
            if ( ionode ) then

              WRITE(stdout,*) "Writing projectors of kpt", ik

              file_exists = .false.
              inquire(file =trim(exportDir)//"/projections"//iotk_index(ik), exist = file_exists)
              if ( .not. file_exists ) then
                open(72, file=trim(exportDir)//"/projections"//iotk_index(ik))
                write(72, '("# Complex projections <beta|psi>. Format: ''(2ES24.15E3)''")')
                do j = 1,  becp%nbnd ! number of bands
                  do i = 1, nkb      ! number of projections
                    write(72,'(2ES24.15E3)') becp%k(i,j)
                  enddo
                enddo
              
                close(72)
              
              endif
            endif
          ENDIF
        ENDIF

        ALLOCATE(l2g_new(local_pw))

        l2g_new = 0
        DO ig = 1, local_pw
          ngg = igk_l2g(ig,ik-iks+1)
          DO ig_ = 1, ngk_g(ik)
            IF(ngg == igwk(ig_,ik)) THEN
              l2g_new(ig) = ig_
              exit
            ENDIF
          ENDDO
        ENDDO
        
        ispin = isk( ik )
        
        if ( ionode ) then

          file_exists = .false.
          inquire(file =trim(exportDir)//"/wfc"//iotk_index(ik), exist = file_exists)
          if ( .not. file_exists ) then
            open (72, file=trim(exportDir)//"/wfc"//iotk_index(ik))
            write(72, '("# Spin : ",i10, " Format: ''(a9, i10)''")') ispin
            write(72, '("# Complex : wavefunction coefficients (a.u.)^(-3/2). Format: ''(2ES24.15E3)''")')
            
            open(73, file=trim(exportDir)//"/projectors"//iotk_index(ik))
            write(73, '("# Complex projectors |beta>. Format: ''(2ES24.15E3)''")')
            write(73,'(2i10)') nkb, ngk_g(ik)
!            WRITE(stdout,*) "Writing Wavefunctions of kpt", ik
!            open(74, file=trim(exportDir)//"/evc"//iotk_index(ik))
!            write(74, '("# Spin : ",i10, " Format: ''(a9, i10)''")') ispin
!            write(74, '("# Complex : wavefunction coefficients (a.u.)^(-3/2). Format: ''(2ES24.15E3)''")')
          endif
        endif
        
        CALL mp_bcast( file_exists, ionode_id, world_comm )
        
        if ( .not. file_exists ) then
          CALL write_restart_wfc(72, exportDir, ik, nkstot, ispin, nspin, &
                                 wfc_scal, evc, twf0, evc, twfm, npw_g, gamma_only, nbnd, &
                                 l2g_new(:),local_pw )
          CALL write_restart_wfc(73, exportDir, ik, nkstot, ispin, nspin, &
                                 wfc_scal, vkb, twf0, evc, twfm, npw_g, gamma_only, nkb, &
                                 l2g_new(:), local_pw )
        endif
      
        if ( .not. file_exists .and. ionode ) then
          close(72)
          close(73)
!          close(74)
        endif
      
        DEALLOCATE(l2g_new)
      ENDDO
    
      CALL deallocate_bec_type ( becp )
    
    ENDIF

    DEALLOCATE( igk_l2g )
    DEALLOCATE( igwk )
    DEALLOCATE ( ngk_g )
END SUBROUTINE write_export

end module wfcExportVASPMod