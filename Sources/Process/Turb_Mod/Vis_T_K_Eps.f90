!==============================================================================!
  subroutine Turb_Mod_Vis_T_K_Eps(turb)
!------------------------------------------------------------------------------!
!   Computes the turbulent viscosity for RANS models.                          !
!                                                                              !
!   In the domain:                                                             !
!   For k-eps model :                                                          !
!                                                                              !
!   vis_t = c_mu * rho * k^2 * eps                                             !
!                                                                              !
!   On the boundary (wall viscosity):                                          !
!   vis_tw = y^+ * vis_t kappa / (E * ln(y^+))                                 !
!                                                                              !
!   For k-eps-v2f model :                                                      !
!                                                                              !
!   vis_t = CmuD * rho * Tsc  * vv                                             !
!------------------------------------------------------------------------------!
  implicit none
!---------------------------------[Arguments]----------------------------------!
  type(Turb_Type), target :: turb
!---------------------------------[Calling]------------------------------------!
  real :: Turbulent_Prandtl_Number
  real :: U_Plus_Log_Law
  real :: U_Plus_Rough_Walls
  real :: Y_Plus_Low_Re
  real :: Y_Plus_Rough_Walls
  real :: Roughness_Coefficient
!-----------------------------------[Locals]-----------------------------------!
  type(Field_Type), pointer :: flow
  type(Grid_Type),  pointer :: grid
  type(Var_Type),   pointer :: u, v, w
  type(Var_Type),   pointer :: kin, eps
  integer                   :: c1, c2, s, c
  real                      :: pr, beta, ebf
  real                      :: u_tan, u_tau
  real                      :: kin_vis, u_plus, y_star, re_t, f_mu
!==============================================================================!
!   Dimensions:                                                                !
!                                                                              !
!   production    p_kin    [m^2/s^3]   | rate-of-strain  shear    [1/s]        !
!   dissipation   eps % n  [m^2/s^3]   | turb. visc.     vis_t    [kg/(m*s)]   !
!   wall shear s. tau_wall [kg/(m*s^2)]| dyn visc.       viscosity[kg/(m*s)]   !
!   density       density  [kg/m^3]    | turb. kin en.   kin % n  [m^2/s^2]    !
!   cell volume   vol      [m^3]       | length          lf       [m]          !
!   left hand s.  A        [kg/s]      | right hand s.   b        [kg*m^2/s^3] !
!   wall visc.    vis_wall [kg/(m*s)]  | kinematic viscosity      [m^2/s]      !
!   thermal cap.  capacity[m^2/(s^2*K)]| therm. conductivity     [kg*m/(s^3*K)]!
!------------------------------------------------------------------------------!
!   p_kin = 2*vis_t / density S_ij S_ij                                        !
!   shear = sqrt(2 S_ij S_ij)                                                  !
!------------------------------------------------------------------------------!

  ! Take aliases
  flow => turb % pnt_flow
  grid => flow % pnt_grid
  call Field_Mod_Alias_Momentum(flow, u, v, w)
  call Turb_Mod_Alias_K_Eps    (turb, kin, eps)

  ! Kinematic viscosities
  kin_vis = viscosity/density

  do c = 1, grid % n_cells
    re_t = density * kin % n(c)**2/(viscosity*eps % n(c))

    y_star = (kin_vis * eps % n(c))**0.25 * grid % wall_dist(c)/kin_vis

    f_mu = (1.0 -     exp(-y_star/14.0))**2   &
         * (1.0 + 5.0*exp(-(re_t/200.0) * (re_t/200.0) ) /re_t**0.75)

    f_mu = min(1.0,f_mu)

    vis_t(c) = f_mu * c_mu * density * kin % n(c)**2  / eps % n(c)
  end do

  do s = 1, grid % n_faces
    c1 = grid % faces_c(1,s)
    c2 = grid % faces_c(2,s)

    if(c2 < 0) then
      if(Grid_Mod_Bnd_Cond_Type(grid,c2) .eq. WALL .or.  &
         Grid_Mod_Bnd_Cond_Type(grid,c2) .eq. WALLFL) then

        u_tan = Field_Mod_U_Tan(flow, s)
        u_tau = c_mu25 * sqrt(kin % n(c1))
        y_plus(c1) = Y_Plus_Low_Re(u_tau, grid % wall_dist(c1), kin_vis)

        ebf = 0.01 * y_plus(c1)**4 / (1.0 + 5.0*y_plus(c1))
        u_plus = U_Plus_Log_Law(y_plus(c1))

        if(y_plus(c1) < 3.0) then
          vis_wall(c1) = vis_t(c1) + viscosity
        else
          vis_wall(c1) =  y_plus(c1) * viscosity         &
                       / (  y_plus(c1) * exp(-1.0*ebf)   &
                          + u_plus     * exp(-1.0/ebf) + TINY)
        end if

        y_plus(c1) = Y_Plus_Low_Re(u_tau, grid % wall_dist(c1), kin_vis)

        if(rough_walls) then
          z_o = Roughness_Coefficient(grid, z_o_f(c1), c1)
          y_plus(c1) = Y_Plus_Rough_Walls(u_tau,                 &
                                          grid % wall_dist(c1),  &
                                          kin_vis)
          u_plus     = U_Plus_Rough_Walls(grid % wall_dist(c1))
          vis_wall(c1) = y_plus(c1) * viscosity * kappa  &
                       / log((grid % wall_dist(c1)+z_o)/z_o)  ! is this U+?
        end if

        if(heat_transfer) then
          pr = viscosity * capacity / conductivity
          pr_t = Turbulent_Prandtl_Number(grid, c1)
          beta = 9.24 * ((pr/pr_t)**0.75 - 1.0)  &
               * (1.0 + 0.28 * exp(-0.007*pr/pr_t))
          ebf = 0.01 * (pr*y_plus(c1)**4  &
              / ((1.0 + 5.0 * pr**3 * y_plus(c1)) + TINY))
          con_wall(c1) =    y_plus(c1) * viscosity * capacity          &
                       / (  y_plus(c1) * pr        * exp(-1.0 * ebf)   &
                          +(u_plus + beta) * pr_t  * exp(-1.0/ebf) + TINY)
        end if
      end if  ! Grid_Mod_Bnd_Cond_Type(grid,c2).eq.WALL or WALLFL
    end if    ! c2 < 0
  end do

  call Comm_Mod_Exchange_Real(grid, vis_t)
  call Comm_Mod_Exchange_Real(grid, vis_wall)

  end subroutine