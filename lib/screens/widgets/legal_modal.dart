import 'package:flutter/material.dart';

/// Shown by both the pre-auth [LoginScreen] footer and `ClientProfileScreen`'s
/// "Términos y Políticas" row — extracted here so the actual legal copy
/// lives in exactly one place instead of two screens slowly drifting apart
/// every time it's amended.
const String kTermsOfServiceText =
    '1. OBJETO Y NATURALEZA DE LA PLATAFORMA\n\n'
    'Mussy opera exclusivamente como un directorio digital de intermediación y vitrina comercial. Su finalidad es conectar de manera directa a clientes o organizadores de eventos con prestadores independientes de servicios artísticos, musicales, de animación, DJs y logística de entretenimiento.\n\n'
    '2. LIMITACIÓN DE RESPONSABILIDAD\n\n'
    'Mussy no es parte de los contratos de prestación de servicios celebrados entre los usuarios y los artistas o proveedores. Por consiguiente, Mussy no asume ninguna responsabilidad por la calidad, cumplimiento, puntualidad, cancelaciones, pagos o disputas derivadas de las contrataciones acordadas de forma externa a través del contacto facilitado por el directorio.\n\n'
    '3. USO ADECUADO DE LOS DATOS DE CONTACTO\n\n'
    'Los números telefónicos y canales de contacto publicados en los perfiles tienen como único propósito propiciar acuerdos comerciales legítimos para eventos. Queda estrictamente prohibido el uso de esta información para fines de suplantación, hostigamiento, campañas masivas de spam o actividades contrarias a la ley colombiana.\n\n'
    '4. PROPIEDAD INTELECTUAL Y CONTENIDO\n\n'
    'Los proveedores y artistas garantizan que cuentan con los derechos de autor, autorizaciones e imágenes de perfil expuestas en sus galerías, liberando a Mussy de cualquier reclamación por infracción de derechos de terceros.';

const String kPrivacyPolicyText =
    '1. RESPONSABLE DEL TRATAMIENTO DE DATOS\n\n'
    'En cumplimiento de la Ley estatutaria 1581 de 2012 y el Decreto reglamentario 1377 de 2013 de Colombia sobre protección de datos personales, informamos que los datos recopilados a través de nuestro sistema de autenticación (nombre, correo electrónico y datos opcionales de perfil o contacto) son tratados bajo rigurosos estándares de seguridad.\n\n'
    '2. FINALIDAD DE LA RECOLECCIÓN\n\n'
    'La información suministrada por los usuarios tiene como únicas finalidades:\n'
    '• Gestionar la creación y autenticación de cuentas de usuario mediante Google.\n'
    '• Facilitar la visualización del directorio de talento y servicios para eventos.\n'
    '• Permitir la comunicación directa entre interesados y artistas a través de canales habilitados (como enlaces de WhatsApp).\n\n'
    '3. NO CESIÓN A TERCEROS\n\n'
    'Sus datos personales no serán comercializados, cedidos, alquilados ni compartidos con terceros con fines publicitarios o comerciales ajenos a la operación interna de la plataforma.\n\n'
    '4. DERECHOS DEL TITULAR (HABEAS DATA)\n\n'
    'Como titular de los datos, usted tiene derecho a conocer, actualizar, rectificar y solicitar la supresión de sus datos personales en cualquier momento, comunicándose directamente con el soporte técnico de Mussy para proceder al retiro de su perfil y registros del sistema.';

Future<void> showLegalModal(
  BuildContext context, {
  required String title,
  required String content,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF121216),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Text(
                  content,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
