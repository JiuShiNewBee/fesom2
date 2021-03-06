MODULE gen_bulk
! Compute heat and momentum exchange coefficients
  use o_mesh
  use i_therm_param
  use i_arrays
  use g_forcing_arrays
  use g_parsup
  use g_sbf, only: atmdata, i_totfl, i_xwind, i_ywind, i_humi, i_qsr, i_qlw, i_tair, i_prec, i_mslp, i_cloud

  implicit none

  public ncar_ocean_fluxes_mode
  public core_coeff_2z
  
  CONTAINS
subroutine ncar_ocean_fluxes_mode 
  ! Compute drag coefficient and the transfer coefficients for evaporation
  ! and sensible heat according to LY2004.
  ! In this routine we assume air temperature and humidity are at the same
  ! height as wind speed. Otherwise, the code should be modified.
  ! There is a parameter z, which sets the height of wind speed. 
  ! For the CORE forcing data, z=10.0 
  !
  ! original note:
  ! Over-ocean fluxes following Large and Yeager (used in NCAR models)           
  ! Coded by Mike Winton (Michael.Winton@noaa.gov) in 2004
  ! A bug was found by Laurent Brodeau (brodeau@gmail.com) in 2007.
  ! Stephen.Griffies@noaa.gov updated the code with the bug fix.  
  ! 
  ! Code from CORE website is adopted to FESOM by Qiang Wang
  ! Reviewed by ??
  !----------------------------------------------------------------------

  integer, parameter :: n_itts = 2
  integer            :: i, j, m
  real(kind=WP) :: cd_n10, ce_n10, ch_n10, cd_n10_rt    ! neutral 10m drag coefficients
  real(kind=WP) :: cd, ce, ch, cd_rt                    ! full drag coefficients @ z
  real(kind=WP) :: zeta, x2, x, psi_m, psi_h, stab      ! stability parameters
  real(kind=WP) :: t, ts, q, qs, u, u10, tv, xx, dux, dvy
  real(kind=WP) :: tstar, qstar, ustar, bstar
  real(kind=WP), parameter :: grav = 9.80, vonkarm = 0.40
  real(kind=WP), parameter :: q1=640380., q2=-5107.4    ! for saturated surface specific humidity
  real(kind=WP), parameter :: zz = 10.0

  do i=1,myDim_nod2d+eDim_nod2d       
     t=tair(i) + tmelt					      ! degree celcium to Kelvin
     ts=t_oc_array(i) + tmelt				      !
     q=shum(i)
     qs=0.98*q1*inv_rhoair*exp(q2/ts) 			      ! L-Y eqn. 5 
     tv = t*(1.0+0.608*q)
     dux=u_wind(i)-u_w(i)
     dvy=v_wind(i)-v_w(i)
     u = max(sqrt(dux**2+dvy**2), 0.5)           	      ! 0.5 m/s floor on wind (undocumented NCAR)
     u10 = u                                                  ! first guess 10m wind

     cd_n10 = (2.7/u10+0.142+0.0764*u10)*1.0e-3                ! L-Y eqn. 6a
     cd_n10_rt = sqrt(cd_n10) 
     ce_n10 = 34.6 *cd_n10_rt*1.0e-3       		      ! L-Y eqn. 6b
     stab = 0.5 + sign(0.5_WP,t-ts)
     ch_n10 = (18.0*stab+32.7*(1.0-stab))*cd_n10_rt*1.e-3      ! L-Y eqn. 6c

     cd = cd_n10                                 	      ! first guess for exchange coeff's at z
     ch = ch_n10
     ce = ce_n10
     do j=1,n_itts                                            ! Monin-Obukhov iteration
        cd_rt = sqrt(cd)
        ustar    = cd_rt*u                                    ! L-Y eqn. 7a
        tstar    = (ch/cd_rt)*(t-ts)              	      ! L-Y eqn. 7b
        qstar    = (ce/cd_rt)*(q-qs)              	      ! L-Y eqn. 7c
        bstar    = grav*(tstar/tv+qstar/(q+1.0/0.608))
        zeta     = vonkarm*bstar*zz/(ustar*ustar) 	      ! L-Y eqn. 8a
        zeta     = sign( min(abs(zeta),10.0_WP), zeta )          ! undocumented NCAR
        x2 = sqrt(abs(1.-16.*zeta))                           ! L-Y eqn. 8b
        x2 = max(x2, 1.0)                                     ! undocumented NCAR
        x = sqrt(x2)

        if (zeta > 0.) then
           psi_m = -5.*zeta                                    ! L-Y eqn. 8c
           psi_h = -5.*zeta                                    ! L-Y eqn. 8c
        else
           psi_m = log((1.+2.*x+x2)*(1+x2)/8.)-2.*(atan(x)-atan(1.0))  ! L-Y eqn. 8d
           psi_h = 2.*log((1.+x2)/2.)                                  ! L-Y eqn. 8e
        end if

        u10 = u/(1.0+cd_n10_rt*(log(zz/10.)-psi_m)/vonkarm)        ! L-Y eqn. 9 !why cd_n10_rt not cd_rt
        cd_n10 = (2.7/u10+0.142+0.0764*u10)*1.e-3                  ! L-Y eqn. 6a again
        cd_n10_rt = sqrt(cd_n10) 
        ce_n10 = 34.6*cd_n10_rt*1.e-3                              ! L-Y eqn. 6b again
        stab = 0.5 + sign(0.5_WP,zeta)
        ch_n10 = (18.0*stab+32.7*(1.0-stab))*cd_n10_rt*1.e-3       ! L-Y eqn. 6c again
        !z0 = 10*exp(-vonkarm/cd_n10_rt)                          ! diagnostic

        xx = (log(zz/10.)-psi_m)/vonkarm
        cd = cd_n10/(1.0+cd_n10_rt*xx)**2             		  ! L-Y 10a
        xx = (log(zz/10.)-psi_h)/vonkarm
        ch = ch_n10/(1.0+ch_n10*xx/cd_n10_rt)*sqrt(cd/cd_n10)     ! 10b (corrected code aug2007)
        ce = ce_n10/(1.0+ce_n10*xx/cd_n10_rt)*sqrt(cd/cd_n10)     ! 10c (corrected code aug2007)
     end do

     cd_atm_oce_arr(i)=cd
     ch_atm_oce_arr(i)=ch
     ce_atm_oce_arr(i)=ce 
  end do

end subroutine ncar_ocean_fluxes_mode
!
!---------------------------------------------------------------------------------------------------
!
subroutine cal_wind_drag_coeff
  ! Compute wind-ice drag coefficient following AOMIP
  !
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !--------------------------------------------------
  
  use o_mesh
  use i_arrays
  use g_forcing_arrays
  use g_parsup
  implicit none

  integer            :: i, m
  real(kind=WP)      :: ws

  do i=1,myDim_nod2d+eDim_nod2d    
     ws=sqrt(u_wind(i)**2+v_wind(i)**2)
     cd_atm_ice_arr(i)=(1.1+0.04*ws)*1.0e-3
  end do

end subroutine cal_wind_drag_coeff
!
SUBROUTINE nemo_ocean_fluxes_mode
!!----------------------------------------------------------------------
!! ** Purpose : Change model variables according to atm fluxes
!! source of original code: NEMO 3.1.1 + NCAR
!!----------------------------------------------------------------------
   IMPLICIT NONE
   integer             :: i
   real(wp)            :: rtmp    ! temporal real
   real(wp)            :: wndm    ! delta of wind module and ocean curent module
   real(wp)            :: wdx,wdy ! delta of wind x/y and ocean curent x/y
   real(wp)            :: q_sat   ! sea surface specific humidity         [kg/kg]
   real(wp), parameter :: rhoa = 1.22 ! air density
   real(wp), parameter :: cpa  = 1000.5         ! specific heat of air
   real(wp), parameter :: Lv   =    2.5e6       ! latent heat of vaporization
   real(wp), parameter :: Stef =    5.67e-8     ! Stefan Boltzmann constant
   real(wp), parameter :: albo =    0.066       ! ocean albedo assumed to be contant
   real(wp)            :: zst     ! surface temperature in Kelvin
   real(wp)           ::  &
      Cd,       &     ! transfer coefficient for momentum         (tau)
      Ch,       &     ! transfer coefficient for sensible heat (Q_sens)
      Ce,       &     ! transfert coefficient for evaporation   (Q_lat)
      t_zu,     &     ! air temp. shifted at zu                     [K]
      q_zu            ! spec. hum.  shifted at zu               [kg/kg]
   real(wp)           :: zevap, zqsb, zqla, zqlw
!!$OMP PARALLEL
!!$OMP DO
   do i = 1, myDim_nod2D+eDim_nod2d
      wdx  = atmdata(i_xwind,i) - u_w(i) ! wind from data - ocean current ( x direction)
      wdy  = atmdata(i_ywind,i) - v_w(i) ! wind from data - ocean current ( y direction)
      wndm = SQRT( wdx * wdx + wdy * wdy )
      zst  = t_oc_array(i)+273.15

      q_sat = 0.98 * 640380. / rhoa * EXP( -5107.4 / zst )

      call core_coeff_2z(2.0_wp, 10.0_wp, zst, atmdata(i_tair,i), &
                        q_sat, atmdata(i_humi,i), wndm, Cd, Ch, Ce, t_zu, q_zu)
     cd_atm_oce_arr(i)=Cd
     ch_atm_oce_arr(i)=Ch
     ce_atm_oce_arr(i)=Ce
   end do
!!$OMP END DO
!!$OMP END PARALLEL
END SUBROUTINE nemo_ocean_fluxes_mode

!---------------------------------------------------------------------------------------------------
SUBROUTINE core_coeff_2z(zt, zu, sst, T_zt, q_sat, q_zt, dU, Cd, Ch, Ce, T_zu, q_zu)
   !!----------------------------------------------------------------------
   !!                      ***  ROUTINE  core_coeff_2z  ***
   !!
   !! ** Purpose :   Computes turbulent transfert coefficients of surface
   !!                fluxes according to Large & Yeager (2004).
   !!
   !! ** Method  :   I N E R T I A L   D I S S I P A T I O N   M E T H O D
   !!      Momentum, Latent and sensible heat exchange coefficients
   !!      Caution: this procedure should only be used in cases when air
   !!      temperature (T_air) and air specific humidity (q_air) are at 2m
   !!      whereas wind (dU) is at 10m.
   !!
   !! References :   Large & Yeager, 2004 : ???
   !! code was adopted from NEMO 3.3.1
   !!----------------------------------------------------------------------
   IMPLICIT NONE
   real(wp)            :: dU10        ! dU                             [m/s]
   real(wp)            :: dT          ! air/sea temperature difference   [K]
   real(wp)            :: dq          ! air/sea humidity difference      [K]
   real(wp)            :: Cd_n10      ! 10m neutral drag coefficient
   real(wp)            :: Ce_n10      ! 10m neutral latent coefficient
   real(wp)            :: Ch_n10      ! 10m neutral sensible coefficient
   real(wp)            :: sqrt_Cd_n10 ! root square of Cd_n10
   real(wp)            :: sqrt_Cd     ! root square of Cd
   real(wp)            :: T_vpot      ! virtual potential temperature    [K]
   real(wp)            :: T_star      ! turbulent scale of tem. fluct.
   real(wp)            :: q_star      ! turbulent humidity of temp. fluct.
   real(wp)            :: U_star      ! turb. scale of velocity fluct.
   real(wp)            :: L           ! Monin-Obukov length              [m]
   real(wp)            :: zeta_u      ! stability parameter at height zu
   real(wp)            :: zeta_t      ! stability parameter at height zt
   real(wp)            :: U_n10       ! neutral wind velocity at 10m     [m]
   real(wp)            :: xlogt , xct , zpsi_hu , zpsi_ht , zpsi_m
   real(wp)            :: stab        ! 1st guess stability test integer
   !!
   real(wp), intent(in)   :: &
      zt,      &     ! height for T_zt and q_zt                   [m]
      zu             ! height for dU                              [m]
   real(wp), intent(in)   ::  &
      sst,      &     ! sea surface temperature              [Kelvin]
      T_zt,     &     ! potential air temperature            [Kelvin]
      q_sat,    &     ! sea surface specific humidity         [kg/kg]
      q_zt,     &     ! specific air humidity                 [kg/kg]
      dU              ! relative wind module |U(zu)-U(0)|       [m/s]
   real(wp), intent(out)  ::  &
      Cd,       &     ! transfer coefficient for momentum         (tau)
      Ch,       &     ! transfer coefficient for sensible heat (Q_sens)
      Ce,       &     ! transfert coefficient for evaporation   (Q_lat)
      T_zu,     &     ! air temp. shifted at zu                     [K]
      q_zu            ! spec. hum.  shifted at zu               [kg/kg]

   integer :: j_itt
   integer,  parameter :: nb_itt = 3   ! number of itterations
   real(wp), parameter ::                        &
      grav   = 9.8,      &  ! gravity
      kappa  = 0.4          ! von Karman's constant
   !!----------------------------------------------------------------------
   !!  * Start
   !! Initial air/sea differences
   dU10 = max(0.5_wp, dU)      !  we don't want to fall under 0.5 m/s
   dT = T_zt - sst
   dq = q_zt - q_sat
   !! Neutral Drag Coefficient :
   stab = 0.5 + sign(0.5_wp,dT)                 ! stab = 1  if dT > 0  -> STABLE
   Cd_n10  = 1E-3*( 2.7/dU10 + 0.142 + dU10/13.09 )
   sqrt_Cd_n10 = sqrt(Cd_n10)
   Ce_n10  = 1E-3*( 34.6 * sqrt_Cd_n10 )
   Ch_n10  = 1E-3*sqrt_Cd_n10*(18*stab + 32.7*(1 - stab))
   !! Initializing transf. coeff. with their first guess neutral equivalents :
   Cd = Cd_n10 ;  Ce = Ce_n10 ;  Ch = Ch_n10 ;  sqrt_Cd = sqrt(Cd)
   !! Initializing z_u values with z_t values :
   T_zu = T_zt ;  q_zu = q_zt

   !!  * Now starting iteration loop
   do j_itt=1, nb_itt
      dT = T_zu - sst ;  dq = q_zu - q_sat ! Updating air/sea differences
      T_vpot = T_zu*(1. + 0.608*q_zu)      ! Updating virtual potential temperature at zu
      U_star = sqrt_Cd*dU10                ! Updating turbulent scales :   (L & Y eq. (7))
      T_star  = Ch/sqrt_Cd*dT              !
      q_star  = Ce/sqrt_Cd*dq              !
      !!
      L = (U_star*U_star) &                ! Estimate the Monin-Obukov length at height zu
           & / (kappa*grav/T_vpot*(T_star*(1.+0.608*q_zu) + 0.608*T_zu*q_star))
      !! Stability parameters :
      zeta_u  = zu/L  ;  zeta_u = sign( min(abs(zeta_u),10.0), zeta_u )
      zeta_t  = zt/L  ;  zeta_t = sign( min(abs(zeta_t),10.0), zeta_t )
      zpsi_hu = psi_h(zeta_u)
      zpsi_ht = psi_h(zeta_t)
      zpsi_m  = psi_m(zeta_u)
      !!
      !! Shifting the wind speed to 10m and neutral stability : (L & Y eq.(9a))
      !   U_n10 = dU10/(1. + sqrt_Cd_n10/kappa*(log(zu/10.) - psi_m(zeta_u)))
      !   In very rare low-wind conditions, the old way of estimating the
      !   neutral wind speed at 10m leads to a negative value that causes the code
      !   to crash. To prevent this a threshold of 0.25m/s is now imposed.
      U_n10 = max(0.25 , dU10/(1. + sqrt_Cd_n10/kappa*(log(zu/10.) - zpsi_m)))
      !!
      !! Shifting temperature and humidity at zu :          (L & Y eq. (9b-9c))
      !T_zu = T_zt - T_star/kappa*(log(zt/zu) + psi_h(zeta_u) - psi_h(zeta_t))
      T_zu = T_zt - T_star/kappa*(log(zt/zu) + zpsi_hu - zpsi_ht)
      !q_zu = q_zt - q_star/kappa*(log(zt/zu) + psi_h(zeta_u) - psi_h(zeta_t))
      q_zu = q_zt - q_star/kappa*(log(zt/zu) + zpsi_hu - zpsi_ht)
      !!
      !! q_zu cannot have a negative value : forcing 0
      stab = 0.5 + sign(0.5_wp,q_zu) ;  q_zu = stab*q_zu
      !!
      !! Updating the neutral 10m transfer coefficients :
      Cd_n10  = 1E-3 * (2.7/U_n10 + 0.142 + U_n10/13.09)    ! L & Y eq. (6a)
      sqrt_Cd_n10 = sqrt(Cd_n10)
      Ce_n10  = 1E-3 * (34.6 * sqrt_Cd_n10)                 ! L & Y eq. (6b)
      stab    = 0.5 + sign(0.5_wp,zeta_u)
      Ch_n10  = 1E-3*sqrt_Cd_n10*(18.*stab + 32.7*(1-stab)) ! L & Y eq. (6c-6d)
      !!
      !!
      !! Shifting the neutral 10m transfer coefficients to (zu,zeta_u) :
      !xct = 1. + sqrt_Cd_n10/kappa*(log(zu/10.) - psi_m(zeta_u))
      xct = 1. + sqrt_Cd_n10/kappa*(log(zu/10.) - zpsi_m)
      Cd = Cd_n10/(xct*xct) ; sqrt_Cd = sqrt(Cd)
      !!
      !xlogt = log(zu/10.) - psi_h(zeta_u)
      xlogt = log(zu/10.) - zpsi_hu
      !!
      xct = 1. + Ch_n10*xlogt/kappa/sqrt_Cd_n10
      Ch  = Ch_n10*sqrt_Cd/sqrt_Cd_n10/xct
      !!
      xct = 1. + Ce_n10*xlogt/kappa/sqrt_Cd_n10
      Ce  = Ce_n10*sqrt_Cd/sqrt_Cd_n10/xct
      !!
         !!
   end do
   !!
END SUBROUTINE core_coeff_2z

FUNCTION psi_h( zta )
   !! Psis, L & Y eq. (8c), (8d), (8e)
   !-------------------------------------------------------------------------------
   real(wp)             :: X2
   real(wp)             :: X
   real(wp)             :: stabit
   !
   real(wp), intent(in) ::   zta
   real(wp)             ::   psi_h
   !-------------------------------------------------------------------------------
   X2 = sqrt(abs(1. - 16.*zta))  ;  X2 = max(X2 , 1.) ;  X  = sqrt(X2)
   stabit    = 0.5 + sign(0.5_wp,zta)
   psi_h = -5.*zta*stabit  &                                       ! Stable
     &    + (1. - stabit)*(2.*log( (1. + X2)/2. ))                 ! Unstable
END FUNCTION psi_h

FUNCTION psi_m( zta )
!! Psis, L & Y eq. (8c), (8d), (8e)
!-------------------------------------------------------------------------------
   real(wp)             :: X2
   real(wp)             :: X
   real(wp)             :: stabit
   !!
   real(wp), intent(in) ::   zta
   real(wp), parameter  :: pi = 3.141592653589793_wp
   real(wp)             :: psi_m
   !-------------------------------------------------------------------------------

   X2 = sqrt(abs(1. - 16.*zta))  ;  X2 = max(X2 , 1.0) ;  X  = sqrt(X2)
   stabit    = 0.5 + sign(0.5_wp,zta)
   psi_m = -5.*zta*stabit  &                                                          ! Stable
      &    + (1. - stabit)*(2*log((1. + X)/2) + log((1. + X2)/2) - 2*atan(X) + pi/2)  ! Unstable
   !
END FUNCTION psi_m
END MODULE gen_bulk
