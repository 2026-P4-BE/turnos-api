package ar.edu.utn.frc.turnos.controller;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

/** Integration test: real Spring context, real JPA repository on H2, HTTP through MockMvc. */
@SpringBootTest
@AutoConfigureMockMvc
class AppointmentApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    private ResultActions createAppointment(String professional, LocalDateTime slot)
            throws Exception {
        String body = """
                {"professional":"%s","patient":"Ana","slot":"%s"}
                """.formatted(professional, slot);
        return mockMvc.perform(post("/api/appointments")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body));
    }

    @Test
    void createsAndFetchesAppointment() throws Exception {
        LocalDateTime slot = LocalDateTime.now().plusDays(10).withNano(0);

        String response = createAppointment("Dr. Create", slot)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("ACTIVE"))
                .andReturn().getResponse().getContentAsString();
        Integer id = JsonPath.read(response, "$.id");

        mockMvc.perform(get("/api/appointments/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.professional").value("Dr. Create"));
        mockMvc.perform(get("/api/appointments"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isNotEmpty());
    }

    @Test
    void returns409WhenSlotIsAlreadyTaken() throws Exception {
        LocalDateTime slot = LocalDateTime.now().plusDays(11).withNano(0);

        createAppointment("Dr. Conflict", slot).andExpect(status().isCreated());
        createAppointment("Dr. Conflict", slot).andExpect(status().isConflict());
    }

    @Test
    void cancelledSlotCanBeBookedAgain() throws Exception {
        LocalDateTime slot = LocalDateTime.now().plusDays(12).withNano(0);

        String response = createAppointment("Dr. Cancel", slot)
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        Integer id = JsonPath.read(response, "$.id");

        mockMvc.perform(delete("/api/appointments/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("CANCELLED"));
        createAppointment("Dr. Cancel", slot).andExpect(status().isCreated());
    }

    @Test
    void returns404ForUnknownAppointment() throws Exception {
        mockMvc.perform(get("/api/appointments/999999")).andExpect(status().isNotFound());
    }

    @Test
    void returns400ForInvalidPayload() throws Exception {
        mockMvc.perform(post("/api/appointments")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"professional\":\"\",\"patient\":\"Ana\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void exposesVersionAndEnvironment() throws Exception {
        mockMvc.perform(get("/api/version"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.version").value("1.0.0"))
                .andExpect(jsonPath("$.env").value("local"));
    }

    @Test
    void healthEndpointIsUp() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
