package ar.edu.utn.frc.turnos.model;

import jakarta.validation.constraints.Future;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.LocalDateTime;

public record AppointmentRequest(
        @NotBlank String professional,
        @NotBlank String patient,
        @NotNull @Future LocalDateTime slot) {
}
