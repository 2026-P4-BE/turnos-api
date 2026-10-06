package ar.edu.utn.frc.turnos.repository;

import ar.edu.utn.frc.turnos.model.Appointment;
import ar.edu.utn.frc.turnos.model.AppointmentStatus;
import java.time.LocalDateTime;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AppointmentRepository extends JpaRepository<Appointment, Long> {

    boolean existsByProfessionalAndSlotAndStatus(
            String professional, LocalDateTime slot, AppointmentStatus status);
}
