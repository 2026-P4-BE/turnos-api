package ar.edu.utn.frc.turnos.model;

import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import java.time.LocalDateTime;

@Entity
public class Appointment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String professional;
    private String patient;
    private LocalDateTime slot;

    @Enumerated(EnumType.STRING)
    private AppointmentStatus status = AppointmentStatus.ACTIVE;

    protected Appointment() {
        // required by JPA
    }

    public Appointment(String professional, String patient, LocalDateTime slot) {
        this.professional = professional;
        this.patient = patient;
        this.slot = slot;
    }

    public Long getId() {
        return id;
    }

    public String getProfessional() {
        return professional;
    }

    public String getPatient() {
        return patient;
    }

    public LocalDateTime getSlot() {
        return slot;
    }

    public AppointmentStatus getStatus() {
        return status;
    }

    public void cancel() {
        this.status = AppointmentStatus.CANCELLED;
    }
}
