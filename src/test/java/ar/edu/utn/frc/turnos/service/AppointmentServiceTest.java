package ar.edu.utn.frc.turnos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import ar.edu.utn.frc.turnos.exception.AppointmentNotFoundException;
import ar.edu.utn.frc.turnos.exception.SlotAlreadyTakenException;
import ar.edu.utn.frc.turnos.model.Appointment;
import ar.edu.utn.frc.turnos.model.AppointmentRequest;
import ar.edu.utn.frc.turnos.model.AppointmentStatus;
import ar.edu.utn.frc.turnos.repository.AppointmentRepository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AppointmentServiceTest {

    private static final LocalDateTime SLOT = LocalDateTime.of(2030, 1, 15, 10, 0);

    @Mock
    private AppointmentRepository repository;

    @InjectMocks
    private AppointmentService service;

    @Test
    void createsAppointmentWhenSlotIsFree() {
        AppointmentRequest request = new AppointmentRequest("Dr. House", "Ana", SLOT);
        when(repository.existsByProfessionalAndSlotAndStatus(
                "Dr. House", SLOT, AppointmentStatus.ACTIVE)).thenReturn(false);
        when(repository.save(any(Appointment.class))).thenAnswer(inv -> inv.getArgument(0));

        Appointment created = service.create(request);

        assertThat(created.getProfessional()).isEqualTo("Dr. House");
        assertThat(created.getStatus()).isEqualTo(AppointmentStatus.ACTIVE);
    }

    @Test
    void rejectsAppointmentWhenSlotIsTaken() {
        AppointmentRequest request = new AppointmentRequest("Dr. House", "Ana", SLOT);
        when(repository.existsByProfessionalAndSlotAndStatus(
                "Dr. House", SLOT, AppointmentStatus.ACTIVE)).thenReturn(true);

        assertThatThrownBy(() -> service.create(request))
                .isInstanceOf(SlotAlreadyTakenException.class);
        verify(repository, never()).save(any());
    }

    @Test
    void cancelMarksAppointmentAsCancelled() {
        Appointment appointment = new Appointment("Dr. House", "Ana", SLOT);
        when(repository.findById(1L)).thenReturn(Optional.of(appointment));
        when(repository.save(appointment)).thenReturn(appointment);

        Appointment cancelled = service.cancel(1L);

        assertThat(cancelled.getStatus()).isEqualTo(AppointmentStatus.CANCELLED);
    }

    @Test
    void findByIdFailsWhenMissing() {
        when(repository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.findById(99L))
                .isInstanceOf(AppointmentNotFoundException.class)
                .hasMessageContaining("99");
    }

    @Test
    void findAllDelegatesToRepository() {
        when(repository.findAll()).thenReturn(List.of(new Appointment("Dr. House", "Ana", SLOT)));

        assertThat(service.findAll()).hasSize(1);
    }
}
