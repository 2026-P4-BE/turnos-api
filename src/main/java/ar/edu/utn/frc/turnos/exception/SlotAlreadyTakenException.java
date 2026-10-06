package ar.edu.utn.frc.turnos.exception;

public class SlotAlreadyTakenException extends RuntimeException {

    public SlotAlreadyTakenException(String message) {
        super(message);
    }
}
