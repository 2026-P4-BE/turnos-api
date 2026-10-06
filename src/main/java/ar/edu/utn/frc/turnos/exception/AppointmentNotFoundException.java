package ar.edu.utn.frc.turnos.exception;

public class AppointmentNotFoundException extends RuntimeException {

    public AppointmentNotFoundException(Long id) {
        super("Appointment " + id + " not found");
    }
}
