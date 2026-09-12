import 'package:flutter/material.dart';

import '../main.dart';
import '../ui/ui_kit.dart';

enum LegalDocumentType { terms, privacy }

class LegalScreen extends StatelessWidget {
  final LegalDocumentType type;

  const LegalScreen({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final title = switch (type) {
      LegalDocumentType.terms => 'Términos y condiciones',
      LegalDocumentType.privacy => 'Política de privacidad',
    };
    final sections = switch (type) {
      LegalDocumentType.terms => _termsSections,
      LegalDocumentType.privacy => _privacySections,
    };
    return Scaffold(
      backgroundColor: CX.bg,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
              children: [
                PremiumSectionHeader(title: title),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: CX.panelDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final section in sections) ...[
                        if (section.title != null)
                          Text(
                            section.title!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        if (section.title != null) const SizedBox(height: 7),
                        Text(
                          section.body,
                          style: const TextStyle(
                            color: CX.muted,
                            height: 1.5,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalSection {
  final String? title;
  final String body;
  const _LegalSection(this.body, {this.title});
}

const _termsSections = [
  _LegalSection(
    'fobal es una plataforma para cuerpos técnicos de fútbol (entrenadores, profes, DTs) que permite organizar planteles, categorías, sesiones de entrenamiento y datos de rendimiento de sus equipos.',
  ),
  _LegalSection(
    'fobal se ofrece "tal cual", sin costo actualmente. Nos reservamos el derecho de introducir planes pagos en el futuro, con aviso previo a los usuarios activos antes de que cualquier cobro entre en vigencia.',
    title: '1. Uso del servicio.',
  ),
  _LegalSection(
    'Sos responsable de mantener la confidencialidad de tu acceso. Cada club manual (no afiliado a la Liga Universitaria) es administrado por la persona que lo creó, quien puede invitar colaboradores con roles definidos (entrenador asistente, preparador físico, visualizador).',
    title: '2. Cuentas.',
  ),
  _LegalSection(
    'La información de jugadores, categorías, sesiones y evaluaciones que cargás es tuya. fobal la almacena para que puedas acceder a ella desde cualquier dispositivo y no se comparte con terceros salvo lo descrito en la Política de Privacidad.',
    title: '3. Datos que cargás.',
  ),
  _LegalSection(
    'Para clubes afiliados a la Liga Universitaria, fobal muestra resultados, fixtures y tablas provistos por esa fuente pública; no los genera ni los garantiza.',
    title: '4. Datos de la Liga Universitaria.',
  ),
  _LegalSection(
    'No está permitido cargar datos falsos de terceros, usar la plataforma para fines ajenos a la gestión deportiva, ni intentar vulnerar la seguridad del servicio.',
    title: '5. Uso aceptable.',
  ),
  _LegalSection(
    'No garantizamos disponibilidad ininterrumpida. Recomendamos exportar copias de seguridad de tu club periódicamente desde la sección de configuración.',
    title: '6. Disponibilidad.',
  ),
  _LegalSection(
    'Podemos actualizar estos términos; los cambios relevantes se notificarán dentro de la plataforma.',
    title: '7. Cambios.',
  ),
  _LegalSection('Consultas a soporte@fobal.com.', title: '8. Contacto.'),
];

const _privacySections = [
  _LegalSection(
    'Correo electrónico (para tu cuenta), y los datos deportivos que vos mismo cargás: jugadores, categorías, sesiones, evaluaciones, asistencia.',
    title: '1. Qué datos recolectamos.',
  ),
  _LegalSection(
    'Exclusivamente para operar la plataforma: mostrarte tu información, sincronizarla entre tus dispositivos, y generar sugerencias de sesiones de entrenamiento (usando un modelo de IA de terceros sobre los datos de tu categoría, nunca datos personales sensibles de menores más allá de nombre y posición).',
    title: '2. Para qué los usamos.',
  ),
  _LegalSection(
    'No vendemos ni compartimos tus datos con terceros con fines comerciales. Usamos proveedores de infraestructura (hosting, base de datos) que procesan los datos únicamente para operar el servicio.',
    title: '3. Con quién los compartimos.',
  ),
  _LegalSection(
    'Si invitás colaboradores a tu club, ellos acceden a los datos de ese club según el rol que les asignes. Podés revocar ese acceso en cualquier momento desde Configuración.',
    title: '4. Colaboradores de club.',
  ),
  _LegalSection(
    'Los datos de jugadores menores de edad son cargados y administrados por el cuerpo técnico adulto responsable, no por los menores directamente.',
    title: '5. Menores de edad.',
  ),
  _LegalSection(
    'Aplicamos medidas razonables de seguridad (autenticación, cifrado en tránsito). Ningún sistema es 100% infalible; recomendamos exportar copias de seguridad periódicas.',
    title: '6. Seguridad.',
  ),
  _LegalSection(
    'Podés pedir la eliminación de tu cuenta y tus datos escribiendo a soporte@fobal.com.',
    title: '7. Tus derechos.',
  ),
  _LegalSection('soporte@fobal.com.', title: '8. Contacto.'),
];
